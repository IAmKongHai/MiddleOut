import XCTest
@testable import MiddleOut

final class WordProcessorTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Verify that a file with invalid binary content triggers invalidDocument error.
    func testInvalidFile_throws() {
        let fakeFile = tempDir.appendingPathComponent("fake.docx")
        // Write random binary data that cannot be parsed as any document format
        var bytes = [UInt8](repeating: 0, count: 256)
        for i in 0..<bytes.count { bytes[i] = UInt8(i & 0xFF) }
        try! Data(bytes).write(to: fakeFile)

        XCTAssertThrowsError(try WordProcessor.process(at: fakeFile, quality: 0.8)) { error in
            // NSAttributedString may throw invalidDocument or the data may be unreadable
            XCTAssertTrue(
                error is WordProcessorError,
                "Expected WordProcessorError, got \(error)"
            )
        }
    }
}
