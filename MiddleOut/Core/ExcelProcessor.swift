// ExcelProcessor.swift
// Converts .xlsx files to JPEG images (one sheet = one JPG) using CoreXLSX for parsing
// and WebViewRenderer for HTML-to-image rendering.

import Foundation
import AppKit
import CoreXLSX

/// Excel 处理过程中可能出现的错误类型
enum ExcelProcessorError: Error, LocalizedError {
    case invalidFile
    case emptyWorkbook
    case sheetParseFailed(String)
    case sheetRenderFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Cannot open .xlsx file"
        case .emptyWorkbook: return "Workbook contains no sheets"
        case .sheetParseFailed(let name): return "Failed to parse sheet: \(name)"
        case .sheetRenderFailed(let name): return "Failed to render sheet: \(name)"
        }
    }
}

/// 将 Excel (.xlsx) 文件的每个 sheet 转换为一张 JPEG 图片。
/// 使用 CoreXLSX 解析表格数据，通过 WebViewRenderer 渲染 HTML 表格为图片。
struct ExcelProcessor {

    /// 每列默认宽度（像素）
    private static let pixelsPerColumn: CGFloat = 150
    /// 视口最小宽度
    private static let minViewportWidth: CGFloat = 800
    /// 视口最大宽度
    private static let maxViewportWidth: CGFloat = 4000

    /// 处理 Excel 文件，为每个 sheet 生成一张 JPEG 图片。
    /// - Parameters:
    ///   - url: .xlsx 文件路径
    ///   - quality: JPEG 压缩质量 (0.0 ~ 1.0)
    /// - Returns: 处理结果数组（每个 sheet 一个）
    static func process(at url: URL, quality: Double) throws -> [ProcessingResult] {
        let fm = FileManager.default
        let inputSize = (try fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0

        // 1. 打开 xlsx 文件
        guard let xlsxFile = XLSXFile(filepath: url.path) else {
            throw ExcelProcessorError.invalidFile
        }

        // 2. 解析工作簿
        let workbooks = try xlsxFile.parseWorkbooks()
        guard let workbook = workbooks.first else {
            throw ExcelProcessorError.emptyWorkbook
        }

        // 3. 解析工作表路径和名称
        let sheetPathsAndNames = try xlsxFile.parseWorksheetPathsAndNames(workbook: workbook)
        guard !sheetPathsAndNames.isEmpty else {
            throw ExcelProcessorError.emptyWorkbook
        }

        // 4. 解析共享字符串表（可选）
        let sharedStrings = try xlsxFile.parseSharedStrings()

        // 5. 创建输出文件夹
        let folderURL = OutputNamer.docOutputFolderURL(for: url)
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // 6. 逐 sheet 处理
        var results: [ProcessingResult] = []
        var errors: [Error] = []

        for (name, path) in sheetPathsAndNames {
            let sheetName = name ?? "Sheet"
            DebugLog.log("Processing Excel sheet: \(sheetName) at path: \(path)")

            do {
                let worksheet = try xlsxFile.parseWorksheet(at: path)
                let rows = worksheet.data?.rows ?? []

                // 生成 HTML 表格
                let html = generateHTML(sheetName: sheetName, rows: rows, sharedStrings: sharedStrings)

                // 计算视口宽度（基于列数）
                let columnCount = maxColumnCount(rows: rows)
                let viewportWidth = calculateViewportWidth(columnCount: columnCount)

                // 渲染 HTML 为图片
                let options = WebViewRenderer.RenderOptions(
                    html: html,
                    viewportWidth: viewportWidth,
                    viewportHeight: nil
                )

                let renderResult: WebViewRenderer.RenderResult
                do {
                    renderResult = try renderSync(options)
                } catch {
                    DebugLog.log("Render failed for sheet \(sheetName): \(error)")
                    errors.append(ExcelProcessorError.sheetRenderFailed(sheetName))
                    continue
                }

                // 写入 JPEG
                let outputURL = OutputNamer.excelSheetURL(for: url, sheetName: sheetName)
                try MarkdownProcessor.writeImageToJPEG(renderResult.image, to: outputURL, quality: quality)

                let outputSize = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
                results.append(ProcessingResult(
                    outputURL: outputURL,
                    inputSize: inputSize,
                    outputSize: outputSize
                ))

                DebugLog.log("Sheet \(sheetName) rendered: \(outputURL.lastPathComponent)")

            } catch {
                DebugLog.log("Failed to parse sheet \(sheetName): \(error)")
                errors.append(ExcelProcessorError.sheetParseFailed(sheetName))
                continue
            }
        }

        // 如果所有 sheet 都失败了，抛出第一个错误
        if results.isEmpty {
            if let firstError = errors.first {
                throw firstError
            }
            throw ExcelProcessorError.emptyWorkbook
        }

        return results
    }

    // MARK: - HTML Generation

    /// 将 sheet 的行列数据转换为 HTML 表格，带 Excel 风格 CSS。
    private static func generateHTML(
        sheetName: String,
        rows: [Row],
        sharedStrings: SharedStrings?
    ) -> String {
        var tableRows = ""

        for row in rows {
            var cells = ""
            // 按列引用排序，确保单元格按顺序排列
            let sortedCells = row.cells.sorted { $0.reference.column < $1.reference.column }

            // 跟踪当前列位置，填充空白单元格
            var currentColIdx = 1
            for cell in sortedCells {
                let cellColIdx = columnIndex(cell.reference.column)
                // 填充跳过的空列
                while currentColIdx < cellColIdx {
                    cells += "<td></td>"
                    currentColIdx += 1
                }

                let value = cellValue(cell, sharedStrings: sharedStrings)
                let escaped = escapeHTML(value)
                cells += "<td>\(escaped)</td>"
                currentColIdx = cellColIdx + 1
            }

            tableRows += "<tr>\(cells)</tr>\n"
        }

        let escapedName = escapeHTML(sheetName)

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                font-size: 28px;
                line-height: 1.4;
                color: #333333;
                background-color: #ffffff;
                padding: 40px;
            }
            h2 {
                font-size: 1.3em;
                color: #1a5e1a;
                margin-bottom: 16px;
                padding-bottom: 8px;
                border-bottom: 2px solid #4caf50;
            }
            table {
                border-collapse: collapse;
                width: 100%;
                margin-top: 8px;
                table-layout: auto;
            }
            th, td {
                border: 1px solid #d0d7de;
                padding: 8px 12px;
                text-align: left;
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;
                max-width: 400px;
            }
            tr:first-child td, tr:first-child th {
                background-color: #f0f6fc;
                font-weight: 600;
                color: #1a1a1a;
            }
            tr:nth-child(even) {
                background-color: #f9fafb;
            }
            tr:hover {
                background-color: #eef3f8;
            }
            td:empty {
                background-color: transparent;
            }
        </style>
        </head>
        <body>
        <h2>\(escapedName)</h2>
        <table>
        \(tableRows)
        </table>
        </body>
        </html>
        """
    }

    // MARK: - Cell Value Extraction

    /// 从单元格中提取文本值，处理共享字符串、内联字符串和数值。
    private static func cellValue(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
        // 共享字符串
        if cell.type == .sharedString,
           let indexStr = cell.value,
           let index = Int(indexStr),
           let shared = sharedStrings,
           index < shared.items.count {
            // 优先取 text，若为空则尝试拼接 richText
            if let text = shared.items[index].text {
                return text
            }
            let richText = shared.items[index].richText
            if !richText.isEmpty {
                return richText.compactMap { $0.text }.joined()
            }
            return ""
        }

        // 内联字符串
        if cell.type == .inlineStr, let text = cell.inlineString?.text {
            return text
        }

        // 数值或其他类型：直接取 value
        if let value = cell.value {
            return value
        }

        return ""
    }

    // MARK: - Helper Methods

    /// 将列引用转换为 1-based 整数索引（A=1, B=2, ..., Z=26, AA=27, ...）
    private static func columnIndex(_ col: ColumnReference) -> Int {
        let chars = Array(col.value.uppercased())
        var result = 0
        for ch in chars {
            result = result * 26 + (Int(ch.asciiValue ?? 65) - 64)
        }
        return result
    }

    /// 计算所有行中最大列数
    private static func maxColumnCount(rows: [Row]) -> Int {
        var maxCol = 0
        for row in rows {
            for cell in row.cells {
                let colIdx = columnIndex(cell.reference.column)
                if colIdx > maxCol {
                    maxCol = colIdx
                }
            }
        }
        return maxCol
    }

    /// 根据列数计算合适的视口宽度
    private static func calculateViewportWidth(columnCount: Int) -> CGFloat {
        let width = CGFloat(columnCount) * pixelsPerColumn
        return min(max(width, minViewportWidth), maxViewportWidth)
    }

    /// HTML 特殊字符转义
    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Render Sync

    /// 同步渲染，兼容主线程和后台线程调用。
    /// - 主线程：使用 RunLoop pumping（避免 semaphore 死锁主线程）
    /// - 后台线程：使用 DispatchSemaphore（后台线程无法驱动主线程 RunLoop）
    private static func renderSync(
        _ options: WebViewRenderer.RenderOptions,
        timeout: TimeInterval = 30
    ) throws -> WebViewRenderer.RenderResult {
        var renderResult: WebViewRenderer.RenderResult?
        var renderError: Error?

        if Thread.isMainThread {
            // 主线程：RunLoop pumping
            var finished = false
            WebViewRenderer.renderAsync(options) { outcome in
                switch outcome {
                case .success(let r): renderResult = r
                case .failure(let e): renderError = e
                }
                finished = true
            }
            let deadline = Date(timeIntervalSinceNow: timeout)
            while !finished && Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }
            if !finished {
                throw WebViewRendererError.renderTimeout
            }
        } else {
            // 后台线程：semaphore + main async
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                WebViewRenderer.renderAsync(options) { outcome in
                    switch outcome {
                    case .success(let r): renderResult = r
                    case .failure(let e): renderError = e
                    }
                    semaphore.signal()
                }
            }
            if semaphore.wait(timeout: .now() + timeout) == .timedOut {
                throw WebViewRendererError.renderTimeout
            }
        }

        if let error = renderError {
            throw error
        }
        return renderResult!
    }
}
