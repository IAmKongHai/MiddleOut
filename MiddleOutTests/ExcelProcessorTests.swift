// ExcelProcessorTests.swift
// Tests for ExcelProcessor: invalid file handling.

import XCTest
@testable import MiddleOut

final class ExcelProcessorTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExcelTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// 写入垃圾数据到 .xlsx 文件，验证抛出 invalidFile 错误
    func testInvalidFile_throws() {
        let fakeXLSX = tempDir.appendingPathComponent("garbage.xlsx")
        let garbageData = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xAB, 0xCD])
        try! garbageData.write(to: fakeXLSX)

        XCTAssertThrowsError(try ExcelProcessor.process(at: fakeXLSX, quality: 0.8)) { error in
            guard case ExcelProcessorError.invalidFile = error else {
                XCTFail("Expected ExcelProcessorError.invalidFile, got \(error)")
                return
            }
        }
    }
}
