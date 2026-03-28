import XCTest
@testable import MiddleOut

final class OutputNamerTests: XCTestCase {

    func testImageOutputName() {
        let input = URL(fileURLWithPath: "/Users/test/photo.heic")
        let output = OutputNamer.imageOutputURL(for: input)
        XCTAssertEqual(output.lastPathComponent, "photo_opt.jpg")
        XCTAssertEqual(output.deletingLastPathComponent().path, "/Users/test")
    }

    func testImageOutputNameForJPG() {
        let input = URL(fileURLWithPath: "/Users/test/photo.jpg")
        let output = OutputNamer.imageOutputURL(for: input)
        XCTAssertEqual(output.lastPathComponent, "photo_opt.jpg")
    }

    func testPDFOutputFolder() {
        let input = URL(fileURLWithPath: "/Users/test/report.pdf")
        let folder = OutputNamer.pdfOutputFolderURL(for: input)
        XCTAssertEqual(folder.lastPathComponent, "report_pages")
        XCTAssertEqual(folder.deletingLastPathComponent().path, "/Users/test")
    }

    func testPDFPageName() {
        let input = URL(fileURLWithPath: "/Users/test/report.pdf")
        let page = OutputNamer.pdfPageURL(for: input, pageIndex: 0)
        XCTAssertEqual(page.lastPathComponent, "report_page_1.jpg")
    }

    func testPDFPageNameMultiDigit() {
        let input = URL(fileURLWithPath: "/Users/test/report.pdf")
        let page = OutputNamer.pdfPageURL(for: input, pageIndex: 9)
        XCTAssertEqual(page.lastPathComponent, "report_page_10.jpg")
    }

    func testUniqueURL_noConflict() {
        let url = URL(fileURLWithPath: "/tmp/middleout_test_noconflict_\(UUID().uuidString).jpg")
        let result = OutputNamer.uniqueURL(for: url)
        XCTAssertEqual(result, url)
    }

    func testUniqueURL_withConflict() throws {
        let dir = FileManager.default.temporaryDirectory
        let base = dir.appendingPathComponent("conflict_test_opt.jpg")
        try Data().write(to: base)
        defer { try? FileManager.default.removeItem(at: base) }

        let result = OutputNamer.uniqueURL(for: base)
        XCTAssertEqual(result.lastPathComponent, "conflict_test_opt_2.jpg")
    }
}
