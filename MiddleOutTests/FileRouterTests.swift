import XCTest
import Foundation
@testable import MiddleOut

final class FileRouterTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileRouterTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helper: create files with specific magic bytes

    private func createFile(_ name: String, bytes: [UInt8]) -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! Data(bytes).write(to: url)
        return url
    }

    private func createJPEG(_ name: String = "photo.jpg") -> URL {
        createFile(name, bytes: [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    }

    private func createPNG(_ name: String = "image.png") -> URL {
        createFile(name, bytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    private func createPDF(_ name: String = "doc.pdf") -> URL {
        createFile(name, bytes: Array("%PDF-1.4".utf8))
    }

    private func createMarkdown(_ name: String = "readme.md") -> URL {
        let url = tempDir.appendingPathComponent(name)
        try! "# Hello World\n\nSome text.".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Create a minimal ZIP with a specific internal file path to simulate Office docs
    private func createZIPWithEntry(_ name: String, internalPath: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        var data = Data()

        let pathBytes = Array(internalPath.utf8)
        let pathLen = UInt16(pathBytes.count)

        // Local file header
        data.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // signature
        data.append(contentsOf: [0x14, 0x00]) // version needed
        data.append(contentsOf: [0x00, 0x00]) // flags
        data.append(contentsOf: [0x00, 0x00]) // compression (stored)
        data.append(contentsOf: [0x00, 0x00]) // mod time
        data.append(contentsOf: [0x00, 0x00]) // mod date
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // crc32
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // compressed size
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // uncompressed size
        data.append(contentsOf: withUnsafeBytes(of: pathLen.littleEndian) { Array($0) }) // filename length
        data.append(contentsOf: [0x00, 0x00]) // extra field length
        data.append(contentsOf: pathBytes) // filename

        let centralOffset = UInt32(data.count)

        // Central directory file header
        data.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // signature
        data.append(contentsOf: [0x14, 0x00]) // version made by
        data.append(contentsOf: [0x14, 0x00]) // version needed
        data.append(contentsOf: [0x00, 0x00]) // flags
        data.append(contentsOf: [0x00, 0x00]) // compression
        data.append(contentsOf: [0x00, 0x00]) // mod time
        data.append(contentsOf: [0x00, 0x00]) // mod date
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // crc32
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // compressed size
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // uncompressed size
        data.append(contentsOf: withUnsafeBytes(of: pathLen.littleEndian) { Array($0) }) // filename length
        data.append(contentsOf: [0x00, 0x00]) // extra field length
        data.append(contentsOf: [0x00, 0x00]) // file comment length
        data.append(contentsOf: [0x00, 0x00]) // disk number start
        data.append(contentsOf: [0x00, 0x00]) // internal attributes
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // external attributes
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // relative offset of local header
        data.append(contentsOf: pathBytes) // filename

        let centralSize = UInt32(data.count) - centralOffset

        // End of central directory
        data.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // signature
        data.append(contentsOf: [0x00, 0x00]) // disk number
        data.append(contentsOf: [0x00, 0x00]) // disk with central dir
        data.append(contentsOf: [0x01, 0x00]) // entries on this disk
        data.append(contentsOf: [0x01, 0x00]) // total entries
        data.append(contentsOf: withUnsafeBytes(of: centralSize.littleEndian) { Array($0) }) // central dir size
        data.append(contentsOf: withUnsafeBytes(of: centralOffset.littleEndian) { Array($0) }) // central dir offset
        data.append(contentsOf: [0x00, 0x00]) // comment length

        try! data.write(to: url)
        return url
    }

    // MARK: - Image identification tests

    func testIdentifyJPEG() {
        let url = createJPEG()
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.images.count, 1)
    }

    func testIdentifyPNG() {
        let url = createPNG()
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.images.count, 1)
    }

    func testIdentifyTIFF() {
        // Little-endian TIFF
        let url = createFile("photo.tiff", bytes: [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00])
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.images.count, 1)
    }

    func testIdentifyWebP() {
        // RIFF....WEBP
        let url = createFile("photo.webp", bytes: [
            0x52, 0x49, 0x46, 0x46,  // RIFF
            0x00, 0x00, 0x00, 0x00,  // file size (placeholder)
            0x57, 0x45, 0x42, 0x50   // WEBP
        ])
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.images.count, 1)
    }

    func testIdentifyHEIC() {
        // ISO BMFF: size(4 bytes) + "ftyp"
        let url = createFile("photo.heic", bytes: [
            0x00, 0x00, 0x00, 0x1C,  // box size
            0x66, 0x74, 0x79, 0x70,  // "ftyp"
            0x68, 0x65, 0x69, 0x63   // "heic"
        ])
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.images.count, 1)
    }

    func testIdentifyPDF() {
        let url = createPDF()
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.pdfs.count, 1)
    }

    // MARK: - Office ZIP identification tests

    func testIdentifyDOCX() {
        let url = createZIPWithEntry("report.docx", internalPath: "word/document.xml")
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.words.count, 1)
    }

    func testIdentifyXLSX() {
        let url = createZIPWithEntry("data.xlsx", internalPath: "xl/workbook.xml")
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.excels.count, 1)
    }

    func testIdentifyPPTX() {
        let url = createZIPWithEntry("slides.pptx", internalPath: "ppt/presentation.xml")
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.ppts.count, 1)
    }

    func testUnknownZIP_skipped() {
        let url = createZIPWithEntry("archive.zip", internalPath: "random/file.txt")
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].reason.contains("unsupported"))
    }

    // MARK: - Markdown identification tests

    func testIdentifyMarkdown() {
        let url = createMarkdown("notes.md")
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.markdowns.count, 1)
    }

    func testIdentifyMarkdownExtension() {
        let url = createMarkdown("notes.markdown")
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.markdowns.count, 1)
    }

    // MARK: - Wrong extension tests (magic bytes take precedence)

    func testWrongExtension_JPEGNamedPNG() {
        let url = createJPEG("photo.png") // JPEG bytes but .png extension
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.images.count, 1, "Should identify as image regardless of extension")
    }

    // MARK: - Corrupted / empty file tests

    func testEmptyFile_skipped() {
        let url = tempDir.appendingPathComponent("empty.jpg")
        try! Data().write(to: url)
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.skipped.count, 1)
    }

    func testCorruptedData_skipped() {
        let url = createFile("garbage.docx", bytes: [0x01, 0x02, 0x03, 0x04])
        let result = FileRouter.classify([url])
        XCTAssertEqual(result.skipped.count, 1)
    }

    // MARK: - Mixed classification test

    func testClassifyMixed() {
        let urls = [
            createJPEG(),
            createPDF(),
            createZIPWithEntry("doc.docx", internalPath: "word/document.xml"),
            createZIPWithEntry("data.xlsx", internalPath: "xl/workbook.xml"),
            createZIPWithEntry("deck.pptx", internalPath: "ppt/presentation.xml"),
            createMarkdown(),
        ]
        let result = FileRouter.classify(urls)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.pdfs.count, 1)
        XCTAssertEqual(result.words.count, 1)
        XCTAssertEqual(result.excels.count, 1)
        XCTAssertEqual(result.ppts.count, 1)
        XCTAssertEqual(result.markdowns.count, 1)
        XCTAssertEqual(result.skipped.count, 0)
    }
}
