import XCTest
@testable import MiddleOut

final class FileRouterTests: XCTestCase {

    func testClassifyImages() {
        let urls = [
            URL(fileURLWithPath: "/test/a.heic"),
            URL(fileURLWithPath: "/test/b.png"),
            URL(fileURLWithPath: "/test/c.tiff"),
            URL(fileURLWithPath: "/test/d.webp"),
            URL(fileURLWithPath: "/test/e.jpg"),
        ]
        let result = FileRouter.classify(urls)
        XCTAssertEqual(result.images.count, 5)
        XCTAssertEqual(result.pdfs.count, 0)
        XCTAssertEqual(result.skipped.count, 0)
    }

    func testClassifyPDF() {
        let urls = [URL(fileURLWithPath: "/test/doc.pdf")]
        let result = FileRouter.classify(urls)
        XCTAssertEqual(result.images.count, 0)
        XCTAssertEqual(result.pdfs.count, 1)
    }

    func testClassifyMixed() {
        let urls = [
            URL(fileURLWithPath: "/test/a.heic"),
            URL(fileURLWithPath: "/test/b.pdf"),
            URL(fileURLWithPath: "/test/c.docx"),
        ]
        let result = FileRouter.classify(urls)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.pdfs.count, 1)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertEqual(result.skipped[0].reason, "unsupported format")
    }

    func testClassifyCaseInsensitive() {
        let urls = [
            URL(fileURLWithPath: "/test/photo.HEIC"),
            URL(fileURLWithPath: "/test/doc.PDF"),
        ]
        let result = FileRouter.classify(urls)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.pdfs.count, 1)
    }

}
