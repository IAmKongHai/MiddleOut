import XCTest
@testable import MiddleOut

final class OutputNamerV2Tests: XCTestCase {

    func testDocOutputFolderURL() {
        let input = URL(fileURLWithPath: "/Users/test/report.docx")
        let folder = OutputNamer.docOutputFolderURL(for: input)
        XCTAssertEqual(folder.lastPathComponent, "report_pages")
        XCTAssertEqual(folder.deletingLastPathComponent().path, "/Users/test")
    }

    func testDocPageURL() {
        let input = URL(fileURLWithPath: "/Users/test/report.docx")
        let page = OutputNamer.docPageURL(for: input, pageIndex: 0)
        XCTAssertEqual(page.lastPathComponent, "report_page_1.jpg")
    }

    func testDocPageURL_multiDigit() {
        let input = URL(fileURLWithPath: "/Users/test/slides.pptx")
        let page = OutputNamer.docPageURL(for: input, pageIndex: 49)
        XCTAssertEqual(page.lastPathComponent, "slides_page_50.jpg")
    }

    func testExcelSheetURL() {
        let input = URL(fileURLWithPath: "/Users/test/data.xlsx")
        let sheet = OutputNamer.excelSheetURL(for: input, sheetName: "Sheet1")
        XCTAssertEqual(sheet.lastPathComponent, "data_Sheet1.jpg")
    }

    func testExcelSheetURL_specialChars() {
        let input = URL(fileURLWithPath: "/Users/test/data.xlsx")
        let sheet = OutputNamer.excelSheetURL(for: input, sheetName: "Sales/Q1:Summary")
        XCTAssertEqual(sheet.lastPathComponent, "data_Sales_Q1_Summary.jpg")
    }

    func testMarkdownSingleOutputURL() {
        let input = URL(fileURLWithPath: "/Users/test/notes.md")
        let output = OutputNamer.markdownSingleOutputURL(for: input)
        XCTAssertEqual(output.lastPathComponent, "notes_opt.jpg")
    }

    func testMarkdownPageURL() {
        let input = URL(fileURLWithPath: "/Users/test/novel.md")
        let page = OutputNamer.docPageURL(for: input, pageIndex: 0)
        XCTAssertEqual(page.lastPathComponent, "novel_page_1.jpg")
    }
}
