// MarkdownProcessorTests.swift
// Tests for MarkdownProcessor: single-page, multi-page, and empty document handling.

import XCTest
@testable import MiddleOut

final class MarkdownProcessorTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testShortMarkdown_singleImage() throws {
        let mdURL = tempDir.appendingPathComponent("short.md")
        try "# Hello\n\nShort content.".write(to: mdURL, atomically: true, encoding: .utf8)

        let results = try MarkdownProcessor.process(at: mdURL, quality: 0.8)
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].outputURL.lastPathComponent.contains("_opt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: results[0].outputURL.path))
    }

    func testLongMarkdown_multiplePages() throws {
        let mdURL = tempDir.appendingPathComponent("long.md")
        var content = "# Long Document\n\n"
        for i in 0..<200 {
            content += "Paragraph \(i): Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam.\n\n"
        }
        try content.write(to: mdURL, atomically: true, encoding: .utf8)

        let results = try MarkdownProcessor.process(at: mdURL, quality: 0.8)
        XCTAssertGreaterThan(results.count, 1, "Long markdown should produce multiple pages")

        let folder = OutputNamer.docOutputFolderURL(for: mdURL)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        for result in results {
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        }
    }

    func testEmptyMarkdown_skipped() {
        let mdURL = tempDir.appendingPathComponent("empty.md")
        try! "".write(to: mdURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try MarkdownProcessor.process(at: mdURL, quality: 0.8)) { error in
            guard case MarkdownProcessorError.emptyDocument = error else {
                XCTFail("Expected emptyDocument, got \(error)")
                return
            }
        }
    }
}
