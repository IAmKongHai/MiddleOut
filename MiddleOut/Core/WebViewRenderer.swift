// WebViewRenderer.swift
// Unified WKWebView off-screen rendering engine.
// Renders HTML to NSImage via WKWebView snapshot.
// Shared by ExcelProcessor and MarkdownProcessor.
// WKWebView must operate on the main thread; callers are on a background queue.

import AppKit
import WebKit

/// WebView 渲染过程中可能出现的错误类型
enum WebViewRendererError: Error, LocalizedError {
    case renderTimeout
    case snapshotFailed
    case webViewLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .renderTimeout: return "WebView rendering timed out (30s)"
        case .snapshotFailed: return "WebView snapshot capture failed"
        case .webViewLoadFailed(let msg): return "WebView load failed: \(msg)"
        }
    }
}

/// 统一的 WKWebView 离屏渲染引擎，将 HTML 渲染为 NSImage。
/// 每次渲染创建全新的 WKWebView 实例，不复用。
struct WebViewRenderer {

    /// 渲染选项，包含 HTML 内容、视口尺寸和可选的 baseURL
    struct RenderOptions {
        let html: String
        let viewportWidth: CGFloat
        /// 固定视口高度；若为 nil 则自动检测内容高度
        let viewportHeight: CGFloat?
        /// 用于解析 HTML 中相对路径资源的 baseURL
        let baseURL: URL?

        init(html: String, viewportWidth: CGFloat, viewportHeight: CGFloat?, baseURL: URL? = nil) {
            self.html = html
            self.viewportWidth = viewportWidth
            self.viewportHeight = viewportHeight
            self.baseURL = baseURL
        }
    }

    /// 渲染结果，包含生成的图片和实际渲染尺寸
    struct RenderResult {
        let image: NSImage
        let actualSize: CGSize
    }

    /// 渲染超时时间（秒）
    private static let timeoutSeconds: Double = 30

    /// 将单个 HTML 字符串渲染为 NSImage。
    /// 此方法会阻塞调用线程（需从后台队列调用），WKWebView 操作在内部调度到主线程执行。
    static func render(_ options: RenderOptions) throws -> RenderResult {
        var result: RenderResult?
        var renderError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            renderOnMainThread(options) { outcome in
                switch outcome {
                case .success(let r): result = r
                case .failure(let e): renderError = e
                }
                semaphore.signal()
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            throw WebViewRendererError.renderTimeout
        }
        if let error = renderError {
            throw error
        }
        guard let finalResult = result else {
            throw WebViewRendererError.snapshotFailed
        }
        return finalResult
    }

    /// 批量渲染多个 HTML 字符串，按顺序依次执行。
    /// 需从后台队列调用。
    static func renderBatch(_ optionsList: [RenderOptions]) throws -> [RenderResult] {
        var results: [RenderResult] = []
        for options in optionsList {
            let result = try render(options)
            results.append(result)
        }
        return results
    }

    /// 异步渲染单个 HTML，完成后通过回调返回结果。
    /// 必须在主线程调用。用于测试场景或已在主线程的调用方。
    static func renderAsync(
        _ options: RenderOptions,
        completion: @escaping (Result<RenderResult, Error>) -> Void
    ) {
        if Thread.isMainThread {
            renderOnMainThread(options, completion: completion)
        } else {
            DispatchQueue.main.async {
                renderOnMainThread(options, completion: completion)
            }
        }
    }

    /// 异步批量渲染，逐个完成后通过回调返回全部结果。
    static func renderBatchAsync(
        _ optionsList: [RenderOptions],
        completion: @escaping (Result<[RenderResult], Error>) -> Void
    ) {
        var results: [RenderResult] = []
        func renderNext(index: Int) {
            guard index < optionsList.count else {
                completion(.success(results))
                return
            }
            // 通过 async 调度确保上一个 WKWebView 完全清理后再创建新实例
            DispatchQueue.main.async {
                renderOnMainThread(optionsList[index]) { outcome in
                    switch outcome {
                    case .success(let r):
                        results.append(r)
                        renderNext(index: index + 1)
                    case .failure(let e):
                        completion(.failure(e))
                    }
                }
            }
        }
        renderNext(index: 0)
    }

    /// 主线程上的渲染实现：创建 WKWebView、加载 HTML、等待完成后截图。
    private static func renderOnMainThread(
        _ options: RenderOptions,
        completion: @escaping (Result<RenderResult, Error>) -> Void
    ) {
        assert(Thread.isMainThread)

        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        let initialHeight = options.viewportHeight ?? 1024
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: options.viewportWidth, height: initialHeight),
            configuration: config
        )

        let delegate = WebViewLoadDelegate()
        webView.navigationDelegate = delegate

        // 通过关联对象强引用 delegate，防止 navigationDelegate (weak) 被提前释放
        objc_setAssociatedObject(webView, "navDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // 加载完成后根据是否需要自动高度检测来决定截图流程
        delegate.onFinish = { [weak webView] in
            guard let webView = webView else {
                completion(.failure(WebViewRendererError.snapshotFailed))
                return
            }

            if options.viewportHeight == nil {
                // 自动检测内容高度
                webView.evaluateJavaScript(
                    "Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.scrollHeight)"
                ) { heightValue, _ in
                    let contentHeight = (heightValue as? CGFloat)
                        ?? (heightValue as? Double).map { CGFloat($0) }
                        ?? 1024
                    let finalHeight = max(contentHeight, 1)
                    webView.frame = NSRect(
                        x: 0, y: 0,
                        width: options.viewportWidth,
                        height: finalHeight
                    )
                    // 短暂延迟确保布局更新完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        takeSnapshot(webView: webView, size: webView.frame.size, completion: completion)
                    }
                }
            } else {
                takeSnapshot(webView: webView, size: webView.frame.size, completion: completion)
            }
        }

        delegate.onFail = { error in
            completion(.failure(WebViewRendererError.webViewLoadFailed(error.localizedDescription)))
        }

        webView.loadHTMLString(options.html, baseURL: options.baseURL)
    }

    /// 对 WKWebView 进行截图并返回结果
    private static func takeSnapshot(
        webView: WKWebView,
        size: CGSize,
        completion: @escaping (Result<RenderResult, Error>) -> Void
    ) {
        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = NSRect(origin: .zero, size: size)

        webView.takeSnapshot(with: snapshotConfig) { image, error in
            if let image = image {
                completion(.success(RenderResult(image: image, actualSize: size)))
            } else {
                completion(.failure(WebViewRendererError.snapshotFailed))
            }
            // 清理：释放关联的 delegate，断开引用，移除 webView
            objc_setAssociatedObject(webView, "navDelegate", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            webView.navigationDelegate = nil
            webView.removeFromSuperview()
        }
    }
}

/// 辅助 delegate 类，用于监听 WKWebView 导航事件（加载完成/失败）
private class WebViewLoadDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    var onFail: ((Error) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFail?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFail?(error)
    }
}
