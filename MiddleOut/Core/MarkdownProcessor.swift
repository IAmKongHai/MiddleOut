// MarkdownProcessor.swift
// Converts Markdown files to JPEG images via cmark HTML conversion and WebView rendering.
// Short content (<=3840px) produces a single _opt.jpg; long content is paginated into _pages/ folder.

import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import cmark_gfm

/// Markdown 处理过程中可能出现的错误类型
enum MarkdownProcessorError: Error, LocalizedError {
    case emptyDocument
    case fileReadFailed
    case htmlConversionFailed
    case imageWriteFailed
    case cropFailed(Int)

    var errorDescription: String? {
        switch self {
        case .emptyDocument: return "Markdown file is empty"
        case .fileReadFailed: return "Cannot read Markdown file"
        case .htmlConversionFailed: return "Failed to convert Markdown to HTML"
        case .imageWriteFailed: return "Failed to write JPEG image"
        case .cropFailed(let page): return "Failed to crop page \(page)"
        }
    }
}

/// 将 Markdown 文件转换为 JPEG 图片的处理器。
/// 短内容生成单张图片，长内容自动分页。
struct MarkdownProcessor {

    /// 渲染视口宽度（2K 分辨率，9:16 比例）
    private static let viewportWidth: CGFloat = 2160
    /// 单页最大高度
    private static let maxPageHeight: CGFloat = 3840
    /// 分页步长（留 100px 重叠防止文字截断）
    private static let pageStep: CGFloat = 3740

    /// 处理 Markdown 文件，返回一个或多个 ProcessingResult。
    /// 使用 renderAsync + RunLoop 驱动方式，兼容主线程和后台线程调用。
    /// - Parameters:
    ///   - url: Markdown 文件路径
    ///   - quality: JPEG 压缩质量 (0.0 ~ 1.0)
    /// - Returns: 处理结果数组
    static func process(at url: URL, quality: Double) throws -> [ProcessingResult] {
        let fm = FileManager.default
        let inputSize = (try fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0

        // 1. 读取 Markdown 文件
        guard let mdString = try? String(contentsOf: url, encoding: .utf8) else {
            throw MarkdownProcessorError.fileReadFailed
        }

        // 2. 检查空文件
        let trimmed = mdString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw MarkdownProcessorError.emptyDocument
        }

        // 3. 通过 cmark 将 Markdown 转换为 HTML
        guard let htmlCString = cmark_markdown_to_html(mdString, mdString.utf8.count, CMARK_OPT_DEFAULT) else {
            throw MarkdownProcessorError.htmlConversionFailed
        }
        let htmlBody = String(cString: htmlCString)
        free(htmlCString)

        // 4. 包装为完整的 HTML 文档（GitHub 风格 CSS，40px 字体适配 2K 屏幕）
        let fullHTML = wrapInHTMLDocument(htmlBody)

        // 5. 首次渲染：自动检测内容高度
        let baseURL = url.deletingLastPathComponent()
        let autoHeightOptions = WebViewRenderer.RenderOptions(
            html: fullHTML,
            viewportWidth: viewportWidth,
            viewportHeight: nil,
            baseURL: baseURL
        )
        let autoResult = try renderSync(autoHeightOptions)
        let contentHeight = autoResult.actualSize.height

        // 6. 根据内容高度决定单页或分页
        if contentHeight <= maxPageHeight {
            // 短内容：直接写入单张图片
            let outputURL = OutputNamer.markdownSingleOutputURL(for: url)
            try writeImageToJPEG(autoResult.image, to: outputURL, quality: quality)

            let outputSize = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            return [ProcessingResult(outputURL: outputURL, inputSize: inputSize, outputSize: outputSize)]
        } else {
            // 长内容：以完整高度重新渲染，然后裁剪分页
            let fullHeightOptions = WebViewRenderer.RenderOptions(
                html: fullHTML,
                viewportWidth: viewportWidth,
                viewportHeight: contentHeight,
                baseURL: baseURL
            )
            let fullResult = try renderSync(fullHeightOptions)

            guard let fullCGImage = fullResult.image.cgImage(
                forProposedRect: nil, context: nil, hints: nil
            ) else {
                throw MarkdownProcessorError.imageWriteFailed
            }

            // 创建输出文件夹
            let folderURL = OutputNamer.docOutputFolderURL(for: url)
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let imagePixelWidth = CGFloat(fullCGImage.width)
            let imagePixelHeight = CGFloat(fullCGImage.height)
            // 计算缩放比例（NSImage 坐标与像素坐标之间的关系）
            let scaleY = imagePixelHeight / contentHeight
            let scaledPageHeight = maxPageHeight * scaleY
            let scaledPageStep = pageStep * scaleY

            var results: [ProcessingResult] = []
            var pageIndex = 0
            var yOffset: CGFloat = 0

            while yOffset < imagePixelHeight {
                let remainingHeight = imagePixelHeight - yOffset
                let cropHeight = min(scaledPageHeight, remainingHeight)

                // CGImage 坐标系：原点在左上角
                let cropRect = CGRect(
                    x: 0,
                    y: yOffset,
                    width: imagePixelWidth,
                    height: cropHeight
                )

                guard let croppedCGImage = fullCGImage.cropping(to: cropRect) else {
                    throw MarkdownProcessorError.cropFailed(pageIndex)
                }

                let pageURL = OutputNamer.docPageURL(for: url, pageIndex: pageIndex)
                let pageImage = NSImage(cgImage: croppedCGImage, size: NSSize(
                    width: cropRect.width / scaleY,
                    height: cropRect.height / scaleY
                ))
                try writeImageToJPEG(pageImage, to: pageURL, quality: quality)

                let outputSize = (try? fm.attributesOfItem(atPath: pageURL.path)[.size] as? UInt64) ?? 0
                results.append(ProcessingResult(
                    outputURL: pageURL,
                    inputSize: inputSize / UInt64(max(1, Int(ceil(imagePixelHeight / scaledPageStep)))),
                    outputSize: outputSize
                ))

                yOffset += scaledPageStep
                pageIndex += 1
            }

            return results
        }
    }

    /// 同步渲染，通过 renderAsync + RunLoop 驱动方式实现。
    /// 兼容主线程调用（避免 semaphore 死锁），也兼容后台线程调用。
    private static func renderSync(
        _ options: WebViewRenderer.RenderOptions,
        timeout: TimeInterval = 30
    ) throws -> WebViewRenderer.RenderResult {
        var renderResult: WebViewRenderer.RenderResult?
        var renderError: Error?
        var finished = false

        // 确保渲染调用在主线程上执行
        let startRender = {
            WebViewRenderer.renderAsync(options) { outcome in
                switch outcome {
                case .success(let r): renderResult = r
                case .failure(let e): renderError = e
                }
                finished = true
            }
        }

        if Thread.isMainThread {
            startRender()
        } else {
            DispatchQueue.main.async { startRender() }
        }

        // 手动驱动 RunLoop 直到渲染完成或超时
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !finished && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if !finished {
            throw WebViewRendererError.renderTimeout
        }
        if let error = renderError {
            throw error
        }
        return renderResult!
    }

    /// 将 NSImage 写入 JPEG 文件。
    /// 此方法为 static，供其他处理器（如 ExcelProcessor）复用。
    /// - Parameters:
    ///   - image: 要写入的图片
    ///   - url: 输出文件路径
    ///   - quality: JPEG 压缩质量 (0.0 ~ 1.0)
    static func writeImageToJPEG(_ image: NSImage, to url: URL, quality: Double) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MarkdownProcessorError.imageWriteFailed
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw MarkdownProcessorError.imageWriteFailed
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw MarkdownProcessorError.imageWriteFailed
        }
    }

    /// 将 HTML body 包装为完整的 HTML 文档，使用 GitHub 风格 CSS。
    /// 字体大小 40px 以适配 2K 分辨率的可读性。
    private static func wrapInHTMLDocument(_ body: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=\(Int(viewportWidth))">
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                font-size: 40px;
                line-height: 1.6;
                color: #24292e;
                background-color: #ffffff;
                padding: 80px;
                max-width: \(Int(viewportWidth))px;
                word-wrap: break-word;
                overflow-wrap: break-word;
            }
            h1 {
                font-size: 2em;
                border-bottom: 1px solid #eaecef;
                padding-bottom: 0.3em;
                margin-top: 1em;
                margin-bottom: 0.5em;
            }
            h2 {
                font-size: 1.5em;
                border-bottom: 1px solid #eaecef;
                padding-bottom: 0.3em;
                margin-top: 1em;
                margin-bottom: 0.5em;
            }
            h3 {
                font-size: 1.25em;
                margin-top: 1em;
                margin-bottom: 0.5em;
            }
            h4, h5, h6 {
                margin-top: 1em;
                margin-bottom: 0.5em;
            }
            p {
                margin-bottom: 1em;
            }
            a {
                color: #0366d6;
                text-decoration: none;
            }
            code {
                font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
                font-size: 0.85em;
                background-color: rgba(27, 31, 35, 0.05);
                padding: 0.2em 0.4em;
                border-radius: 3px;
            }
            pre {
                background-color: #f6f8fa;
                border-radius: 6px;
                padding: 1em;
                overflow-x: auto;
                margin-bottom: 1em;
            }
            pre code {
                background-color: transparent;
                padding: 0;
            }
            blockquote {
                border-left: 4px solid #dfe2e5;
                padding: 0.5em 1em;
                color: #6a737d;
                margin-bottom: 1em;
            }
            ul, ol {
                padding-left: 2em;
                margin-bottom: 1em;
            }
            li {
                margin-bottom: 0.25em;
            }
            table {
                border-collapse: collapse;
                width: 100%;
                margin-bottom: 1em;
            }
            th, td {
                border: 1px solid #dfe2e5;
                padding: 0.5em 1em;
                text-align: left;
            }
            th {
                background-color: #f6f8fa;
                font-weight: 600;
            }
            img {
                max-width: 100%;
                height: auto;
            }
            hr {
                border: none;
                border-top: 1px solid #eaecef;
                margin: 1.5em 0;
            }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
