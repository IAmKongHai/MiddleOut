import XCTest
import AppKit
@testable import MiddleOut

final class ImageProcessorTests: XCTestCase {

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

    /// Helper: create a PNG file at the given URL
    private func createTestPNG(at url: URL, width: Int = 100, height: Int = 100) throws {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create test PNG")
            return
        }
        try pngData.write(to: url)
    }

    func testProcessPNG() throws {
        let input = tempDir.appendingPathComponent("test.png")
        try createTestPNG(at: input)

        let result = try ImageProcessor.process(at: input, quality: 0.8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        XCTAssertEqual(result.outputURL.pathExtension, "jpg")
        XCTAssertTrue(result.outputURL.lastPathComponent.contains("_opt"))
    }

    func testProcessJPG_recompresses() throws {
        let pngURL = tempDir.appendingPathComponent("test_src.png")
        try createTestPNG(at: pngURL)

        let jpgInput = tempDir.appendingPathComponent("photo.jpg")
        let image = NSImage(contentsOf: pngURL)!
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpgData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 1.0]) else {
            XCTFail("Failed to create JPG")
            return
        }
        try jpgData.write(to: jpgInput)

        let result = try ImageProcessor.process(at: jpgInput, quality: 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        let inputSize = try FileManager.default.attributesOfItem(atPath: jpgInput.path)[.size] as! UInt64
        let outputSize = try FileManager.default.attributesOfItem(atPath: result.outputURL.path)[.size] as! UInt64
        XCTAssertLessThan(outputSize, inputSize)
    }

    func testProcessFakeHEIC_throws() throws {
        let fakeFile = tempDir.appendingPathComponent("fake.heic")
        try "this is not an image".data(using: .utf8)!.write(to: fakeFile)

        XCTAssertThrowsError(try ImageProcessor.process(at: fakeFile, quality: 0.8)) { error in
            guard case ImageProcessorError.invalidImage = error else {
                XCTFail("Expected invalidImage error, got \(error)")
                return
            }
        }
    }
}
