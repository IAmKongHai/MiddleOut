import XCTest
import AppKit
@testable import MiddleOut

final class WebViewRendererTests: XCTestCase {

    /// 在主线程上执行异步渲染并手动驱动 RunLoop 直到完成。
    private func renderSync(_ options: WebViewRenderer.RenderOptions, timeout: TimeInterval = 30) throws -> WebViewRenderer.RenderResult {
        var renderResult: WebViewRenderer.RenderResult?
        var renderError: Error?
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
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        if !finished {
            throw WebViewRendererError.renderTimeout
        }
        if let error = renderError {
            throw error
        }
        return renderResult!
    }

    func testRenderSimpleHTML() throws {
        let html = "<html><body><h1>Hello</h1><p>World</p></body></html>"
        let options = WebViewRenderer.RenderOptions(
            html: html,
            viewportWidth: 800,
            viewportHeight: 600
        )

        let result = try renderSync(options)
        XCTAssertNotNil(result.image)
        XCTAssertEqual(result.image.size.width, 800, accuracy: 1.0)
        XCTAssertEqual(result.image.size.height, 600, accuracy: 1.0)
    }

    func testRenderAutoHeight() throws {
        let html = """
        <html><body style="margin:0;padding:0;">
        <div style="width:400px;height:1200px;background:red;"></div>
        </body></html>
        """
        let options = WebViewRenderer.RenderOptions(
            html: html,
            viewportWidth: 400,
            viewportHeight: nil
        )

        let result = try renderSync(options)
        XCTAssertNotNil(result.image)
        XCTAssertEqual(result.image.size.width, 400, accuracy: 1.0)
        XCTAssertGreaterThanOrEqual(result.actualSize.height, 1200)
    }

    func testRenderBatch() throws {
        let htmlPages = [
            "<html><body><p>Page 1</p></body></html>",
            "<html><body><p>Page 2</p></body></html>",
        ]
        let optionsList = htmlPages.map {
            WebViewRenderer.RenderOptions(html: $0, viewportWidth: 400, viewportHeight: 300)
        }

        // 批量渲染：逐个调用 renderSync，确保每次渲染的 RunLoop 都被正确驱动
        var results: [WebViewRenderer.RenderResult] = []
        for options in optionsList {
            let result = try renderSync(options)
            results.append(result)
        }

        XCTAssertEqual(results.count, 2)
        for result in results {
            XCTAssertNotNil(result.image)
        }
    }

    func testRenderEmptyHTML() throws {
        let options = WebViewRenderer.RenderOptions(
            html: "<html><body></body></html>",
            viewportWidth: 400,
            viewportHeight: 300
        )
        let result = try renderSync(options)
        XCTAssertNotNil(result.image)
    }
}
