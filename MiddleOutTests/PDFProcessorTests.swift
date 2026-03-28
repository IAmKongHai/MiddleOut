import XCTest
import PDFKit
@testable import MiddleOut

final class PDFProcessorTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiddleOutTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Helper: create a minimal 2-page PDF
    private func createTestPDF(at url: URL) throws {
        let pdfDoc = PDFDocument()

        for i in 0..<2 {
            let page = PDFPage()
            pdfDoc.insert(page, at: i)
        }

        guard pdfDoc.write(to: url) else {
            XCTFail("Failed to create test PDF")
            return
        }
    }

    func testProcessPDF_createsFolder() throws {
        let input = tempDir.appendingPathComponent("report.pdf")
        try createTestPDF(at: input)

        let results = try PDFProcessor.process(at: input, quality: 0.8)

        XCTAssertEqual(results.count, 2)

        let folderURL = OutputNamer.pdfOutputFolderURL(for: input)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        XCTAssertEqual(results[0].outputURL.lastPathComponent, "report_page_1.jpg")
        XCTAssertEqual(results[1].outputURL.lastPathComponent, "report_page_2.jpg")
    }

    func testProcessFakePDF_throws() throws {
        let fakeFile = tempDir.appendingPathComponent("fake.pdf")
        try "not a pdf".data(using: .utf8)!.write(to: fakeFile)

        XCTAssertThrowsError(try PDFProcessor.process(at: fakeFile, quality: 0.8)) { error in
            guard case PDFProcessorError.invalidPDF = error else {
                XCTFail("Expected invalidPDF error, got \(error)")
                return
            }
        }
    }
}
