# MiddleOut V2 多格式支持 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 MiddleOut 添加 Word (.docx)、Excel (.xlsx)、PowerPoint (.pptx)、Markdown (.md) 到 JPEG 的转换能力。

**Architecture:** 方案 C — 平行处理器 + 共享 WebViewRenderer 分层。FileRouter 升级为 magic bytes 两级识别。Excel 和 Markdown 共享 WKWebView 渲染管线，Word 用 NSAttributedString + Core Text 分页，PPT 用 PPTXKit 渲染。不动 V1 已有的 ImageProcessor / PDFProcessor。

**Tech Stack:** Swift 5.9+, macOS 13.0+, CoreXLSX (SPM), PPTXKit/pptx-swift (SPM), swift-cmark (SPM), NSAttributedString, Core Text, WKWebView, ImageIO

**Spec:** `docs/superpowers/specs/2026-03-30-middleout-v2-multiformat-design.md`

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `MiddleOut/Core/FileRouter.swift` | Magic bytes 两级识别，新增 FileCategory enum |
| Modify | `MiddleOut/Core/OutputNamer.swift` | 新增文档类命名方法（docOutputFolderURL, sheetURL, markdownOutputURL 等） |
| Modify | `MiddleOut/Core/ProcessingCoordinator.swift` | 新增 dispatch 分支，扩展 ProcessingSummary |
| Create | `MiddleOut/Core/WebViewRenderer.swift` | 统一 WKWebView 离屏渲染引擎 |
| Create | `MiddleOut/Core/MarkdownProcessor.swift` | cmark → HTML → WebViewRenderer |
| Create | `MiddleOut/Core/ExcelProcessor.swift` | CoreXLSX → HTML table → WebViewRenderer |
| Create | `MiddleOut/Core/WordProcessor.swift` | NSAttributedString + Core Text 分页渲染 |
| Create | `MiddleOut/Core/PPTProcessor.swift` | PPTXKit 渲染幻灯片 |
| Modify | `MiddleOutTests/FileRouterTests.swift` | Magic bytes 识别测试 |
| Create | `MiddleOutTests/OutputNamerV2Tests.swift` | 新格式命名测试 |
| Create | `MiddleOutTests/WebViewRendererTests.swift` | WKWebView 渲染测试 |
| Create | `MiddleOutTests/MarkdownProcessorTests.swift` | Markdown 转换测试 |
| Create | `MiddleOutTests/ExcelProcessorTests.swift` | Excel 转换测试 |
| Create | `MiddleOutTests/WordProcessorTests.swift` | Word 转换测试 |
| Create | `MiddleOutTests/PPTProcessorTests.swift` | PPT 转换测试 |
| Create | `MiddleOutTests/Resources/` | 测试用样本文件 |

---

## Task 1: 添加 SPM 依赖

**Files:**
- Modify: `MiddleOut.xcodeproj/project.pbxproj` (via Xcode CLI / Swift Package Manager)

- [ ] **Step 1: 通过 Xcode 命令添加 CoreXLSX**

在 Xcode 项目中添加 SPM 依赖。因为 .xcodeproj 的 pbxproj 文件不适合手动编辑，通过 `xcodebuild -resolvePackageDependencies` 验证。

先手动编辑 project.pbxproj，在 `XCRemoteSwiftPackageReference` section 中添加三个包，或者通过 Xcode GUI 添加：

- CoreXLSX: `https://github.com/CoreOffice/CoreXLSX.git`, up to next major from `0.14.0`
- pptx-swift: `https://github.com/codelynx/pptx-swift.git`, up to next major from `1.0.0`
- swift-cmark: `https://github.com/swiftlang/swift-cmark.git`, up to next major from `0.4.0`

注意：CoreXLSX 会自动引入 XMLCoder 和 ZIPFoundation 作为传递依赖。

- [ ] **Step 2: 验证依赖解析成功**

Run: `cd /Users/konghai/Code_local/Project/MiddleOut && xcodebuild -resolvePackageDependencies -project MiddleOut.xcodeproj -scheme MiddleOut 2>&1 | tail -5`

Expected: 输出中包含 "Resolve Package Graph" 且无错误

- [ ] **Step 3: 验证构建通过**

Run: `xcodebuild -project MiddleOut.xcodeproj -scheme MiddleOut -configuration Debug build 2>&1 | tail -3`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MiddleOut.xcodeproj/project.pbxproj MiddleOut.xcodeproj/project.xcworkspace
git commit -m "chore: add CoreXLSX, PPTXKit, swift-cmark SPM dependencies"
```

---

## Task 2: FileRouter — Magic Bytes 两级识别

**Files:**
- Modify: `MiddleOut/Core/FileRouter.swift`
- Modify: `MiddleOutTests/FileRouterTests.swift`
- Create: `MiddleOutTests/Resources/` (测试用假文件)

- [ ] **Step 1: 创建测试资源目录和辅助方法**

在测试目录下创建 Resources 文件夹（如果不存在），后续 Task 的测试资源也放这里。

Run: `mkdir -p /Users/konghai/Code_local/Project/MiddleOut/MiddleOutTests/Resources`

- [ ] **Step 2: 写 FileRouter 的失败测试**

修改 `MiddleOutTests/FileRouterTests.swift`，替换为完整的新测试。新的 FileRouter 用 magic bytes 识别，不再依赖扩展名（Markdown 除外），所以测试需要创建带正确文件头的临时文件。

```swift
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
        Data(bytes).write(to: url, options: [])  // force try in test is fine
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
        // Minimal ZIP: local file header + central directory + end of central directory
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
```

- [ ] **Step 3: 运行测试确认失败**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/FileRouterTests 2>&1 | grep -E "(Test Case|FAIL|error:)" | head -20`

Expected: 编译失败，因为 `FileRouter.ClassificationResult` 还没有 `words`/`excels`/`ppts`/`markdowns` 字段

- [ ] **Step 4: 实现 FileRouter magic bytes 两级识别**

替换 `MiddleOut/Core/FileRouter.swift` 为：

```swift
// FileRouter.swift
// Classifies files by magic bytes (binary header) with ZIP internal structure check.
// Falls back to extension only for plain-text formats (Markdown).

import Foundation

/// File category determined by content inspection
enum FileCategory {
    case image
    case pdf
    case word
    case excel
    case ppt
    case markdown
}

struct FileRouter {

    /// Classification result containing categorized file URLs
    struct ClassificationResult {
        let images: [URL]
        let pdfs: [URL]
        let words: [URL]
        let excels: [URL]
        let ppts: [URL]
        let markdowns: [URL]
        let skipped: [(url: URL, reason: String)]
    }

    /// Markdown file extensions (plain text — no magic bytes available)
    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    /// Classify a list of URLs by inspecting file content.
    static func classify(_ urls: [URL]) -> ClassificationResult {
        var images: [URL] = []
        var pdfs: [URL] = []
        var words: [URL] = []
        var excels: [URL] = []
        var ppts: [URL] = []
        var markdowns: [URL] = []
        var skipped: [(url: URL, reason: String)] = []

        for url in urls {
            switch identifyCategory(url) {
            case .image:    images.append(url)
            case .pdf:      pdfs.append(url)
            case .word:     words.append(url)
            case .excel:    excels.append(url)
            case .ppt:      ppts.append(url)
            case .markdown: markdowns.append(url)
            case .none:     skipped.append((url: url, reason: "unsupported format"))
            }
        }

        return ClassificationResult(
            images: images, pdfs: pdfs, words: words,
            excels: excels, ppts: ppts, markdowns: markdowns,
            skipped: skipped
        )
    }

    /// Identify a single file's category by inspecting its content.
    /// Returns nil if the file cannot be identified or is unsupported.
    static func identifyCategory(_ url: URL) -> FileCategory? {
        // Read first 16 bytes for magic bytes check
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { handle.closeFile() }

        guard let headerData = try? handle.read(upToCount: 16), headerData.count >= 4 else {
            return nil
        }
        let bytes = Array(headerData)

        // JPEG: FF D8 FF
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return .image
        }

        // PNG: 89 50 4E 47
        if bytes.count >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return .image
        }

        // TIFF: 49 49 2A 00 (little endian) or 4D 4D 00 2A (big endian)
        if bytes.count >= 4 {
            let isLittleEndianTIFF = bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00
            let isBigEndianTIFF = bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A
            if isLittleEndianTIFF || isBigEndianTIFF {
                return .image
            }
        }

        // WebP: RIFF....WEBP (bytes 0-3: RIFF, bytes 8-11: WEBP)
        if bytes.count >= 12
            && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return .image
        }

        // HEIC: ISO BMFF container — "ftyp" at offset 4
        if bytes.count >= 8
            && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            return .image
        }

        // PDF: %PDF
        if bytes.count >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 {
            return .pdf
        }

        // ZIP: PK\x03\x04 — check internal structure for Office formats
        if bytes.count >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04 {
            return identifyZIPContent(at: url)
        }

        // Fallback: extension-based check for plain text formats
        let ext = url.pathExtension.lowercased()
        if markdownExtensions.contains(ext) {
            return .markdown
        }

        return nil
    }

    /// Check ZIP internal structure to distinguish docx/xlsx/pptx.
    /// Reads only the central directory (file names), does not decompress content.
    private static func identifyZIPContent(at url: URL) -> FileCategory? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Find End of Central Directory record (search backwards for signature 50 4B 05 06)
        let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        var eocdOffset = -1
        let bytes = Array(data)

        // Search from end, EOCD is at most 65535+22 bytes from end
        let searchStart = max(0, bytes.count - 65557)
        for i in stride(from: bytes.count - 4, through: searchStart, by: -1) {
            if bytes[i] == eocdSignature[0] && bytes[i+1] == eocdSignature[1]
                && bytes[i+2] == eocdSignature[2] && bytes[i+3] == eocdSignature[3] {
                eocdOffset = i
                break
            }
        }
        guard eocdOffset >= 0, eocdOffset + 22 <= bytes.count else { return nil }

        // Parse EOCD: central directory offset (4 bytes at eocdOffset+16)
        let cdOffset = Int(
            UInt32(bytes[eocdOffset+16])
            | (UInt32(bytes[eocdOffset+17]) << 8)
            | (UInt32(bytes[eocdOffset+18]) << 16)
            | (UInt32(bytes[eocdOffset+19]) << 24)
        )
        let entryCount = Int(
            UInt16(bytes[eocdOffset+10]) | (UInt16(bytes[eocdOffset+11]) << 8)
        )

        guard cdOffset >= 0, cdOffset < bytes.count else { return nil }

        // Walk central directory entries, collect file names
        var offset = cdOffset
        var fileNames: [String] = []

        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count else { break }
            // Verify central directory header signature
            guard bytes[offset] == 0x50 && bytes[offset+1] == 0x4B
                && bytes[offset+2] == 0x01 && bytes[offset+3] == 0x02 else { break }

            let nameLen = Int(UInt16(bytes[offset+28]) | (UInt16(bytes[offset+29]) << 8))
            let extraLen = Int(UInt16(bytes[offset+30]) | (UInt16(bytes[offset+31]) << 8))
            let commentLen = Int(UInt16(bytes[offset+32]) | (UInt16(bytes[offset+33]) << 8))

            guard offset + 46 + nameLen <= bytes.count else { break }
            if let name = String(bytes: bytes[(offset+46)..<(offset+46+nameLen)], encoding: .utf8) {
                fileNames.append(name)
            }

            offset += 46 + nameLen + extraLen + commentLen
        }

        // Check for Office document markers
        let hasWordMarker = fileNames.contains { $0.hasPrefix("word/") }
        let hasExcelMarker = fileNames.contains { $0.hasPrefix("xl/") }
        let hasPPTMarker = fileNames.contains { $0.hasPrefix("ppt/") }

        if hasWordMarker { return .word }
        if hasExcelMarker { return .excel }
        if hasPPTMarker { return .ppt }

        return nil // Unknown ZIP content
    }
}
```

- [ ] **Step 5: 运行测试确认全部通过**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/FileRouterTests 2>&1 | grep -E "(Test Case|Executed)" | tail -20`

Expected: 所有 test case PASSED, `Executed N tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add MiddleOut/Core/FileRouter.swift MiddleOutTests/FileRouterTests.swift
git commit -m "feat: upgrade FileRouter to magic bytes identification with ZIP inspection"
```

---

## Task 3: OutputNamer 扩展 — 新格式命名方法

**Files:**
- Modify: `MiddleOut/Core/OutputNamer.swift`
- Create: `MiddleOutTests/OutputNamerV2Tests.swift`

- [ ] **Step 1: 写失败测试**

创建 `MiddleOutTests/OutputNamerV2Tests.swift`：

```swift
import XCTest
@testable import MiddleOut

final class OutputNamerV2Tests: XCTestCase {

    // MARK: - Document folder URL (shared by Word, Excel, PPT, long Markdown)

    func testDocOutputFolderURL() {
        let input = URL(fileURLWithPath: "/Users/test/report.docx")
        let folder = OutputNamer.docOutputFolderURL(for: input)
        XCTAssertEqual(folder.lastPathComponent, "report_pages")
        XCTAssertEqual(folder.deletingLastPathComponent().path, "/Users/test")
    }

    // MARK: - Document page URL (Word, PPT)

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

    // MARK: - Excel sheet URL

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

    // MARK: - Markdown output URL (short content — single image)

    func testMarkdownSingleOutputURL() {
        let input = URL(fileURLWithPath: "/Users/test/notes.md")
        let output = OutputNamer.markdownSingleOutputURL(for: input)
        XCTAssertEqual(output.lastPathComponent, "notes_opt.jpg")
    }

    // MARK: - Markdown page URL (long content — multiple pages)

    func testMarkdownPageURL() {
        let input = URL(fileURLWithPath: "/Users/test/novel.md")
        let page = OutputNamer.docPageURL(for: input, pageIndex: 0)
        XCTAssertEqual(page.lastPathComponent, "novel_page_1.jpg")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/OutputNamerV2Tests 2>&1 | grep -E "(error:|FAIL)" | head -10`

Expected: 编译失败，`docOutputFolderURL`、`docPageURL`、`excelSheetURL`、`markdownSingleOutputURL` 不存在

- [ ] **Step 3: 实现 OutputNamer 新方法**

在 `MiddleOut/Core/OutputNamer.swift` 的 `struct OutputNamer` 末尾（`uniqueURL` 方法之后、struct 的 `}` 之前）添加：

```swift
    // MARK: - V2 Document Naming

    /// Generate the output folder URL for a document: same directory, `name_pages/`
    /// Used by Word, Excel, PPT, and long Markdown files.
    static func docOutputFolderURL(for input: URL) -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let dir = input.deletingLastPathComponent()
        return dir.appendingPathComponent("\(name)_pages")
    }

    /// Generate a page URL inside the document output folder: `name_page_N.jpg`
    /// Used by Word, PPT, and long Markdown files. 1-indexed.
    static func docPageURL(for input: URL, pageIndex: Int) -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let folder = docOutputFolderURL(for: input)
        return folder.appendingPathComponent("\(name)_page_\(pageIndex + 1).jpg")
    }

    /// Generate a sheet URL inside the Excel output folder: `name_SheetName.jpg`
    /// Special characters in sheet name (/ : \\ * ? " < > |) are replaced with underscore.
    static func excelSheetURL(for input: URL, sheetName: String) -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let folder = docOutputFolderURL(for: input)
        let sanitized = sanitizeSheetName(sheetName)
        return folder.appendingPathComponent("\(name)_\(sanitized).jpg")
    }

    /// Generate output URL for short Markdown (single-page): `name_opt.jpg`
    static func markdownSingleOutputURL(for input: URL) -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let dir = input.deletingLastPathComponent()
        let output = dir.appendingPathComponent("\(name)_opt.jpg")
        return uniqueURL(for: output)
    }

    /// Replace characters that are invalid in file names.
    private static func sanitizeSheetName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/:\\*?\"<>|")
        return name.unicodeScalars
            .map { invalidChars.contains($0) ? "_" : String($0) }
            .joined()
    }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/OutputNamerV2Tests 2>&1 | grep -E "(Test Case|Executed)" | tail -15`

Expected: 所有测试通过

- [ ] **Step 5: 确认 V1 测试仍然通过**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/OutputNamerTests 2>&1 | grep "Executed"`

Expected: `Executed 7 tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add MiddleOut/Core/OutputNamer.swift MiddleOutTests/OutputNamerV2Tests.swift
git commit -m "feat: add OutputNamer methods for Word, Excel, PPT, Markdown naming"
```

---

## Task 4: WebViewRenderer — 统一 WKWebView 渲染引擎

**Files:**
- Create: `MiddleOut/Core/WebViewRenderer.swift`
- Create: `MiddleOutTests/WebViewRendererTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `MiddleOutTests/WebViewRendererTests.swift`：

```swift
import XCTest
import AppKit
@testable import MiddleOut

final class WebViewRendererTests: XCTestCase {

    func testRenderSimpleHTML() throws {
        let html = "<html><body><h1>Hello</h1><p>World</p></body></html>"
        let options = WebViewRenderer.RenderOptions(
            html: html,
            viewportWidth: 800,
            viewportHeight: 600
        )

        let result = try WebViewRenderer.render(options)
        XCTAssertNotNil(result.image)
        // Image dimensions should match viewport
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
            viewportHeight: nil  // auto-height
        )

        let result = try WebViewRenderer.render(options)
        XCTAssertNotNil(result.image)
        XCTAssertEqual(result.image.size.width, 400, accuracy: 1.0)
        // Height should accommodate content (at least 1200)
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

        let results = try WebViewRenderer.renderBatch(optionsList)
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
        // Should succeed without crashing, producing a blank image
        let result = try WebViewRenderer.render(options)
        XCTAssertNotNil(result.image)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/WebViewRendererTests 2>&1 | grep -E "(error:|FAIL)" | head -5`

Expected: 编译失败，`WebViewRenderer` 不存在

- [ ] **Step 3: 实现 WebViewRenderer**

创建 `MiddleOut/Core/WebViewRenderer.swift`：

```swift
// WebViewRenderer.swift
// Unified WKWebView off-screen rendering engine.
// Renders HTML to NSImage via WKWebView snapshot.
// Shared by ExcelProcessor and MarkdownProcessor.
// WKWebView must operate on the main thread; callers are on a background queue.

import AppKit
import WebKit

enum WebViewRendererError: Error, LocalizedError {
    case renderTimeout
    case snapshotFailed
    case webViewLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .renderTimeout: return "WebView rendering timed out (30s)"
        case .snapshotFailed: return "WebView snapshot capture failed"
        case .webViewLoadFailed(let msg): return "WebView load failed: \(msg)"
        }
    }
}

struct WebViewRenderer {

    struct RenderOptions {
        let html: String
        let viewportWidth: CGFloat
        let viewportHeight: CGFloat?   // nil = auto-detect from content
        let baseURL: URL?              // for resolving relative paths (images in Markdown)

        init(html: String, viewportWidth: CGFloat, viewportHeight: CGFloat?, baseURL: URL? = nil) {
            self.html = html
            self.viewportWidth = viewportWidth
            self.viewportHeight = viewportHeight
            self.baseURL = baseURL
        }
    }

    struct RenderResult {
        let image: NSImage
        let actualSize: CGSize
    }

    private static let timeoutSeconds: Double = 30

    /// Render a single HTML string to an NSImage.
    /// This method blocks the calling thread (must be called from a background queue).
    /// WKWebView work is dispatched to the main thread internally.
    static func render(_ options: RenderOptions) throws -> RenderResult {
        var result: RenderResult?
        var renderError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            renderOnMainThread(options) { outcome in
                switch outcome {
                case .success(let r): result = r
                case .failure(let e): renderError = e
                }
                semaphore.signal()
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            throw WebViewRendererError.renderTimeout
        }
        if let error = renderError {
            throw error
        }
        guard let finalResult = result else {
            throw WebViewRendererError.snapshotFailed
        }
        return finalResult
    }

    /// Render multiple HTML strings sequentially.
    static func renderBatch(_ optionsList: [RenderOptions]) throws -> [RenderResult] {
        var results: [RenderResult] = []
        for options in optionsList {
            let result = try render(options)
            results.append(result)
        }
        return results
    }

    /// Main-thread rendering implementation. Creates a WKWebView, loads HTML,
    /// waits for completion, takes snapshot, then cleans up.
    private static func renderOnMainThread(
        _ options: RenderOptions,
        completion: @escaping (Result<RenderResult, Error>) -> Void
    ) {
        assert(Thread.isMainThread)

        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        let initialHeight = options.viewportHeight ?? 1024
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: options.viewportWidth, height: initialHeight),
            configuration: config
        )

        // Navigation delegate to detect load completion
        let delegate = WebViewLoadDelegate()
        webView.navigationDelegate = delegate

        delegate.onFinish = { [weak webView] in
            guard let webView = webView else {
                completion(.failure(WebViewRendererError.snapshotFailed))
                return
            }

            // If auto-height, measure content height via JS and resize
            if options.viewportHeight == nil {
                webView.evaluateJavaScript(
                    "Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.scrollHeight)"
                ) { heightValue, _ in
                    let contentHeight = (heightValue as? CGFloat)
                        ?? (heightValue as? Double).map { CGFloat($0) }
                        ?? 1024
                    let finalHeight = max(contentHeight, 1)
                    webView.frame = NSRect(
                        x: 0, y: 0,
                        width: options.viewportWidth,
                        height: finalHeight
                    )
                    // Small delay to allow re-layout after resize
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        takeSnapshot(webView: webView, size: webView.frame.size, completion: completion)
                    }
                }
            } else {
                takeSnapshot(webView: webView, size: webView.frame.size, completion: completion)
            }
        }

        delegate.onFail = { error in
            completion(.failure(WebViewRendererError.webViewLoadFailed(error.localizedDescription)))
        }

        webView.loadHTMLString(options.html, baseURL: options.baseURL)
    }

    private static func takeSnapshot(
        webView: WKWebView,
        size: CGSize,
        completion: @escaping (Result<RenderResult, Error>) -> Void
    ) {
        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = NSRect(origin: .zero, size: size)

        webView.takeSnapshot(with: snapshotConfig) { image, error in
            if let image = image {
                completion(.success(RenderResult(image: image, actualSize: size)))
            } else {
                completion(.failure(WebViewRendererError.snapshotFailed))
            }
            // Clean up WebView
            webView.navigationDelegate = nil
            webView.removeFromSuperview()
        }
    }
}

/// Helper delegate class to observe WKWebView navigation events.
private class WebViewLoadDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    var onFail: ((Error) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFail?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFail?(error)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/WebViewRendererTests 2>&1 | grep -E "(Test Case|Executed)" | tail -10`

Expected: 所有测试通过

- [ ] **Step 5: Commit**

```bash
git add MiddleOut/Core/WebViewRenderer.swift MiddleOutTests/WebViewRendererTests.swift
git commit -m "feat: add WebViewRenderer for off-screen HTML-to-image rendering"
```

---

## Task 5: MarkdownProcessor — cmark → HTML → WebViewRenderer

**Files:**
- Create: `MiddleOut/Core/MarkdownProcessor.swift`
- Create: `MiddleOutTests/MarkdownProcessorTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `MiddleOutTests/MarkdownProcessorTests.swift`：

```swift
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
        // Generate enough content to exceed one 3840px page
        var content = "# Long Document\n\n"
        for i in 0..<200 {
            content += "Paragraph \(i): Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam.\n\n"
        }
        try content.write(to: mdURL, atomically: true, encoding: .utf8)

        let results = try MarkdownProcessor.process(at: mdURL, quality: 0.8)
        XCTAssertGreaterThan(results.count, 1, "Long markdown should produce multiple pages")

        // Check output folder exists
        let folder = OutputNamer.docOutputFolderURL(for: mdURL)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // Verify all output files exist
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/MarkdownProcessorTests 2>&1 | grep -E "(error:|FAIL)" | head -5`

Expected: 编译失败

- [ ] **Step 3: 实现 MarkdownProcessor**

创建 `MiddleOut/Core/MarkdownProcessor.swift`：

```swift
// MarkdownProcessor.swift
// Converts Markdown files to JPEG images via cmark HTML conversion + WebViewRenderer.
// Short content → single _opt.jpg; long content → paginated _pages/ folder.
// Viewport: 2160×3840 (9:16, 2K resolution), page step 3740px (100px overlap).

import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import cmark

enum MarkdownProcessorError: Error, LocalizedError {
    case readFailed
    case emptyDocument
    case parseFailed
    case renderTimeout
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .readFailed: return "cannot read markdown file"
        case .emptyDocument: return "empty markdown file"
        case .parseFailed: return "failed to parse markdown"
        case .renderTimeout: return "rendering timed out"
        case .renderFailed(let msg): return "render failed: \(msg)"
        }
    }
}

struct MarkdownProcessor {

    private static let viewportWidth: CGFloat = 2160
    private static let pageHeight: CGFloat = 3840
    private static let pageStep: CGFloat = 3740  // 3840 - 100 overlap

    /// Process a Markdown file: render to one or more JPEG images.
    static func process(at url: URL, quality: Double) throws -> [ProcessingResult] {
        // Read file
        guard let mdString = try? String(contentsOf: url, encoding: .utf8) else {
            throw MarkdownProcessorError.readFailed
        }

        let trimmed = mdString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MarkdownProcessorError.emptyDocument
        }

        // Convert markdown to HTML using cmark
        guard let htmlCString = cmark_markdown_to_html(mdString, mdString.utf8.count, CMARK_OPT_DEFAULT) else {
            throw MarkdownProcessorError.parseFailed
        }
        let htmlBody = String(cString: htmlCString)
        free(htmlCString)

        // Wrap in styled HTML document
        let fullHTML = wrapInHTMLDocument(htmlBody)

        // Render full content to get actual height
        let baseURL = url.deletingLastPathComponent()
        let renderOptions = WebViewRenderer.RenderOptions(
            html: fullHTML,
            viewportWidth: viewportWidth,
            viewportHeight: nil,  // auto-detect content height
            baseURL: baseURL
        )

        let renderResult: WebViewRenderer.RenderResult
        do {
            renderResult = try WebViewRenderer.render(renderOptions)
        } catch {
            throw MarkdownProcessorError.renderFailed(error.localizedDescription)
        }

        let contentHeight = renderResult.actualSize.height
        let fm = FileManager.default
        let inputSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0

        // Single page: content fits in one viewport
        if contentHeight <= pageHeight {
            let outputURL = OutputNamer.markdownSingleOutputURL(for: url)
            try writeImageToJPEG(renderResult.image, url: outputURL, quality: quality)

            let outputSize = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            return [ProcessingResult(outputURL: outputURL, inputSize: inputSize, outputSize: outputSize)]
        }

        // Multiple pages: render full height then paginate via cropping
        // First, render at full content height
        let fullRenderOptions = WebViewRenderer.RenderOptions(
            html: fullHTML,
            viewportWidth: viewportWidth,
            viewportHeight: contentHeight,
            baseURL: baseURL
        )
        let fullRender = try WebViewRenderer.render(fullRenderOptions)
        let fullImage = fullRender.image

        // Create output folder
        let folderURL = OutputNamer.docOutputFolderURL(for: url)
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var results: [ProcessingResult] = []
        var yOffset: CGFloat = 0
        var pageIndex = 0

        while yOffset < contentHeight {
            let remainingHeight = contentHeight - yOffset
            let cropHeight = min(pageHeight, remainingHeight)

            // Crop the page region from the full image
            guard let pageImage = cropImage(fullImage, rect: NSRect(
                x: 0, y: yOffset,
                width: viewportWidth, height: cropHeight
            )) else {
                pageIndex += 1
                yOffset += pageStep
                continue
            }

            let outputURL = OutputNamer.docPageURL(for: url, pageIndex: pageIndex)
            try writeImageToJPEG(pageImage, url: outputURL, quality: quality)

            let outputSize = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            let inputSizePerPage = inputSize / UInt64(max(1, Int(ceil(contentHeight / pageStep))))
            results.append(ProcessingResult(
                outputURL: outputURL,
                inputSize: inputSizePerPage,
                outputSize: outputSize
            ))

            pageIndex += 1
            yOffset += pageStep
        }

        return results
    }

    /// Wrap HTML body in a complete document with reading-friendly CSS.
    private static func wrapInHTMLDocument(_ body: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                font-size: 40px;
                line-height: 1.6;
                color: #1a1a1a;
                background: #ffffff;
                margin: 60px;
                padding: 0;
                max-width: \(Int(viewportWidth))px;
            }
            h1 { font-size: 64px; margin: 48px 0 24px; }
            h2 { font-size: 52px; margin: 40px 0 20px; }
            h3 { font-size: 44px; margin: 32px 0 16px; }
            p { margin: 16px 0; }
            code {
                font-family: "SF Mono", Menlo, Consolas, monospace;
                font-size: 36px;
                background: #f0f0f0;
                padding: 4px 8px;
                border-radius: 4px;
            }
            pre {
                background: #f6f6f6;
                padding: 24px;
                border-radius: 8px;
                overflow-x: auto;
            }
            pre code { background: none; padding: 0; }
            img { max-width: 100%; height: auto; }
            blockquote {
                border-left: 6px solid #ddd;
                padding-left: 24px;
                margin-left: 0;
                color: #555;
            }
            table { border-collapse: collapse; width: 100%; margin: 16px 0; }
            th, td { border: 1px solid #ddd; padding: 12px 16px; text-align: left; }
            th { background: #f6f6f6; }
            a { color: #0366d6; }
            hr { border: none; border-top: 2px solid #eee; margin: 32px 0; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Crop a region from an NSImage.
    private static func cropImage(_ image: NSImage, rect: NSRect) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        // NSImage coordinate system: origin at bottom-left. CGImage: origin at top-left.
        let flippedY = CGFloat(cgImage.height) - rect.origin.y - rect.size.height
        let cropRect = CGRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
    }

    /// Write an NSImage to a JPEG file at the given URL.
    static func writeImageToJPEG(_ image: NSImage, url: URL, quality: Double) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw MarkdownProcessorError.renderFailed("cannot get CGImage from NSImage")
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1, nil
        ) else {
            throw MarkdownProcessorError.renderFailed("cannot create JPEG destination")
        }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw MarkdownProcessorError.renderFailed("cannot write JPEG")
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/MarkdownProcessorTests 2>&1 | grep -E "(Test Case|Executed)" | tail -10`

Expected: 所有测试通过

- [ ] **Step 5: Commit**

```bash
git add MiddleOut/Core/MarkdownProcessor.swift MiddleOutTests/MarkdownProcessorTests.swift
git commit -m "feat: add MarkdownProcessor with cmark HTML rendering and pagination"
```

---

## Task 6: ExcelProcessor — CoreXLSX → HTML → WebViewRenderer

**Files:**
- Create: `MiddleOut/Core/ExcelProcessor.swift`
- Create: `MiddleOutTests/ExcelProcessorTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `MiddleOutTests/ExcelProcessorTests.swift`：

```swift
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

    func testInvalidFile_throws() {
        let fakeFile = tempDir.appendingPathComponent("fake.xlsx")
        try! "not an xlsx".data(using: .utf8)!.write(to: fakeFile)

        XCTAssertThrowsError(try ExcelProcessor.process(at: fakeFile, quality: 0.8)) { error in
            guard case ExcelProcessorError.invalidFile = error else {
                XCTFail("Expected invalidFile, got \(error)")
                return
            }
        }
    }

    // Note: Testing with a real .xlsx requires a test resource file.
    // Place a small test.xlsx in MiddleOutTests/Resources/ and add to the test target.
    // For now, the invalid file test verifies error handling works.
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/ExcelProcessorTests 2>&1 | grep -E "(error:|FAIL)" | head -5`

Expected: 编译失败

- [ ] **Step 3: 实现 ExcelProcessor**

创建 `MiddleOut/Core/ExcelProcessor.swift`：

```swift
// ExcelProcessor.swift
// Converts Excel .xlsx files to JPEG images: one image per sheet.
// Parses with CoreXLSX, generates HTML tables, renders via WebViewRenderer.

import Foundation
import AppKit
import CoreXLSX
import ImageIO
import UniformTypeIdentifiers

enum ExcelProcessorError: Error, LocalizedError {
    case invalidFile
    case emptyWorkbook
    case sheetParseFailed(String)
    case sheetRenderFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "corrupted or invalid xlsx file"
        case .emptyWorkbook: return "workbook has no sheets"
        case .sheetParseFailed(let name): return "failed to parse sheet: \(name)"
        case .sheetRenderFailed(let name): return "failed to render sheet: \(name)"
        }
    }
}

struct ExcelProcessor {

    /// Process an xlsx file: render each sheet as a JPEG image.
    static func process(at url: URL, quality: Double) throws -> [ProcessingResult] {
        guard let xlsxFile = XLSXFile(filepath: url.path) else {
            throw ExcelProcessorError.invalidFile
        }

        let workbooks = try xlsxFile.parseWorkbooks()
        guard let workbook = workbooks.first else {
            throw ExcelProcessorError.emptyWorkbook
        }

        let sheetPaths = try xlsxFile.parseWorksheetPathsAndNames(workbook: workbook)
        guard !sheetPaths.isEmpty else {
            throw ExcelProcessorError.emptyWorkbook
        }

        let fm = FileManager.default
        let inputSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let inputSizePerSheet = inputSize / UInt64(max(1, sheetPaths.count))

        // Create output folder
        let folderURL = OutputNamer.docOutputFolderURL(for: url)
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // Parse shared strings for cell value lookup
        let sharedStrings = try? xlsxFile.parseSharedStrings()

        var results: [ProcessingResult] = []

        for (name, path) in sheetPaths {
            let sheetName = name ?? "Sheet\(results.count + 1)"

            let worksheet: Worksheet
            do {
                worksheet = try xlsxFile.parseWorksheet(at: path)
            } catch {
                DebugLog.log("WARNING: failed to parse sheet '\(sheetName)': \(error)")
                continue  // skip this sheet, continue with others
            }

            let html = generateHTML(for: worksheet, sheetName: sheetName, sharedStrings: sharedStrings)

            // Render via WebViewRenderer — auto-height to fit all content
            let renderOptions = WebViewRenderer.RenderOptions(
                html: html,
                viewportWidth: calculateViewportWidth(for: worksheet),
                viewportHeight: nil
            )

            let renderResult: WebViewRenderer.RenderResult
            do {
                renderResult = try WebViewRenderer.render(renderOptions)
            } catch {
                DebugLog.log("WARNING: failed to render sheet '\(sheetName)': \(error)")
                continue
            }

            let outputURL = OutputNamer.excelSheetURL(for: url, sheetName: sheetName)
            try MarkdownProcessor.writeImageToJPEG(renderResult.image, url: outputURL, quality: quality)

            let outputSize = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            results.append(ProcessingResult(
                outputURL: outputURL,
                inputSize: inputSizePerSheet,
                outputSize: outputSize
            ))
        }

        if results.isEmpty && !sheetPaths.isEmpty {
            throw ExcelProcessorError.sheetRenderFailed("all sheets failed")
        }

        return results
    }

    /// Generate an HTML table from a worksheet.
    private static func generateHTML(
        for worksheet: Worksheet,
        sheetName: String,
        sharedStrings: SharedStrings?
    ) -> String {
        guard let rows = worksheet.data?.rows, !rows.isEmpty else {
            return wrapInHTMLDocument("<p>Empty sheet: \(sheetName)</p>", title: sheetName)
        }

        // Find max column count across all rows
        let maxCol = rows.flatMap { $0.cells }.compactMap { $0.reference.column }.max()
        let colCount = maxCol.map { Int($0.value.unicodeScalars.first!.value) - Int(Character("A").unicodeScalars.first!.value) + 1 } ?? 1

        var tableHTML = "<table>\n"

        for row in rows {
            tableHTML += "<tr>\n"
            // Build a dictionary for quick cell lookup by column
            var cellMap: [String: Cell] = [:]
            for cell in row.cells {
                let colLetter = cell.reference.column.value
                cellMap[colLetter] = cell
            }

            // Iterate columns A through max
            for colIndex in 0..<colCount {
                let colLetter = String(Character(UnicodeScalar(Int(Character("A").unicodeScalars.first!.value) + colIndex)!))
                let tag = row.cells.first?.reference.row == 1 ? "th" : "td"

                if let cell = cellMap[colLetter] {
                    let value = cellValue(cell, sharedStrings: sharedStrings)
                    tableHTML += "  <\(tag)>\(escapeHTML(value))</\(tag)>\n"
                } else {
                    tableHTML += "  <\(tag)></\(tag)>\n"
                }
            }
            tableHTML += "</tr>\n"
        }
        tableHTML += "</table>"

        return wrapInHTMLDocument(tableHTML, title: sheetName)
    }

    /// Extract the display value from a cell.
    private static func cellValue(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
        // If cell has an inline string
        if let inlineString = cell.inlineString?.text {
            return inlineString
        }

        // If cell references shared strings
        if cell.type == .sharedString,
           let value = cell.value,
           let index = Int(value),
           let sharedStrings = sharedStrings,
           index < sharedStrings.items.count {
            return sharedStrings.items[index].text ?? ""
        }

        // Numeric or other value
        return cell.value ?? ""
    }

    /// Calculate viewport width based on column count.
    private static func calculateViewportWidth(for worksheet: Worksheet) -> CGFloat {
        let colCount = worksheet.data?.rows.flatMap { $0.cells }
            .compactMap { $0.reference.column }
            .map { $0.value }
            .reduce(into: Set<String>()) { $0.insert($1) }
            .count ?? 1
        // ~150px per column, minimum 800, maximum 4000
        return CGFloat(min(4000, max(800, colCount * 150)))
    }

    private static func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func wrapInHTMLDocument(_ body: String, title: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
                font-size: 14px;
                margin: 20px;
                background: #ffffff;
            }
            h2 { font-size: 18px; color: #333; margin-bottom: 12px; }
            table {
                border-collapse: collapse;
                width: 100%;
                font-size: 13px;
            }
            th {
                background: #f0f0f0;
                font-weight: 600;
                text-align: left;
                padding: 8px 12px;
                border: 1px solid #d0d0d0;
            }
            td {
                padding: 6px 12px;
                border: 1px solid #d0d0d0;
                vertical-align: top;
            }
            tr:nth-child(even) td { background: #fafafa; }
        </style>
        </head>
        <body>
        <h2>\(escapeHTML(title))</h2>
        \(body)
        </body>
        </html>
        """
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/ExcelProcessorTests 2>&1 | grep -E "(Test Case|Executed)" | tail -5`

Expected: 测试通过

- [ ] **Step 5: Commit**

```bash
git add MiddleOut/Core/ExcelProcessor.swift MiddleOutTests/ExcelProcessorTests.swift
git commit -m "feat: add ExcelProcessor with CoreXLSX parsing and HTML table rendering"
```

---

## Task 7: WordProcessor — NSAttributedString + Core Text 分页

**Files:**
- Create: `MiddleOut/Core/WordProcessor.swift`
- Create: `MiddleOutTests/WordProcessorTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `MiddleOutTests/WordProcessorTests.swift`：

```swift
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

    func testInvalidFile_throws() {
        let fakeFile = tempDir.appendingPathComponent("fake.docx")
        try! "this is not a docx".data(using: .utf8)!.write(to: fakeFile)

        XCTAssertThrowsError(try WordProcessor.process(at: fakeFile, quality: 0.8)) { error in
            guard case WordProcessorError.invalidDocument = error else {
                XCTFail("Expected invalidDocument, got \(error)")
                return
            }
        }
    }

    // Note: Full integration test requires a real .docx test resource.
    // Add a small test.docx to MiddleOutTests/Resources/ for comprehensive testing.
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/WordProcessorTests 2>&1 | grep -E "(error:|FAIL)" | head -5`

Expected: 编译失败

- [ ] **Step 3: 实现 WordProcessor**

创建 `MiddleOut/Core/WordProcessor.swift`：

```swift
// WordProcessor.swift
// Converts Word .docx files to JPEG images using NSAttributedString + Core Text pagination.
// Each page is rendered at 2x A4 resolution (1190×1684 pixels).

import Foundation
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

enum WordProcessorError: Error, LocalizedError {
    case invalidDocument
    case emptyDocument
    case renderFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidDocument: return "corrupted or invalid Word document"
        case .emptyDocument: return "empty Word document"
        case .renderFailed(let page): return "failed to render page \(page + 1)"
        }
    }
}

struct WordProcessor {

    // A4 at 2x scale: 595pt × 842pt → 1190 × 1684 pixels
    private static let pageWidthPt: CGFloat = 595
    private static let pageHeightPt: CGFloat = 842
    private static let scale: CGFloat = 2.0
    private static let marginPt: CGFloat = 50  // page margin in points

    /// Process a .docx file: render each page as a JPEG.
    static func process(at url: URL, quality: Double) throws -> [ProcessingResult] {
        // Load docx via NSAttributedString
        let attributedString: NSAttributedString
        do {
            attributedString = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.docFormat],
                documentAttributes: nil
            )
        } catch {
            // Try .docFormat first (handles .doc), fall back to reading as generic rich text
            do {
                attributedString = try NSAttributedString(
                    url: url,
                    options: [:],  // Let NSAttributedString auto-detect
                    documentAttributes: nil
                )
            } catch {
                throw WordProcessorError.invalidDocument
            }
        }

        guard attributedString.length > 0 else {
            throw WordProcessorError.emptyDocument
        }

        // Paginate using Core Text
        let textWidth = pageWidthPt - (marginPt * 2)
        let textHeight = pageHeightPt - (marginPt * 2)

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        var pages: [CFRange] = []
        var currentIndex = 0
        let totalLength = attributedString.length

        while currentIndex < totalLength {
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: textWidth, height: textHeight), transform: nil)
            let frameRange = CFRange(location: currentIndex, length: 0)
            let frame = CTFramesetterCreateFrame(framesetter, frameRange, path, nil)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length == 0 { break }  // Safety: no progress means infinite loop

            pages.append(visibleRange)
            currentIndex += visibleRange.length
        }

        guard !pages.isEmpty else {
            throw WordProcessorError.emptyDocument
        }

        let fm = FileManager.default
        let inputSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let inputSizePerPage = inputSize / UInt64(max(1, pages.count))

        // Create output folder
        let folderURL = OutputNamer.docOutputFolderURL(for: url)
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var results: [ProcessingResult] = []

        for (pageIndex, pageRange) in pages.enumerated() {
            let pixelWidth = Int(pageWidthPt * scale)
            let pixelHeight = Int(pageHeightPt * scale)

            guard let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else {
                throw WordProcessorError.renderFailed(pageIndex)
            }

            // White background
            context.setFillColor(CGColor.white)
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

            // Scale for 2x rendering
            context.scaleBy(x: scale, y: scale)

            // Translate to apply margins
            context.translateBy(x: marginPt, y: marginPt)

            // Core Text renders with origin at bottom-left (matching CGContext)
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: textWidth, height: textHeight), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, pageRange, path, nil)
            CTFrameDraw(frame, context)

            guard let cgImage = context.makeImage() else {
                throw WordProcessorError.renderFailed(pageIndex)
            }

            let outputURL = OutputNamer.docPageURL(for: url, pageIndex: pageIndex)

            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1, nil
            ) else {
                throw WordProcessorError.renderFailed(pageIndex)
            }

            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

            guard CGImageDestinationFinalize(destination) else {
                throw WordProcessorError.renderFailed(pageIndex)
            }

            let outputSize = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            results.append(ProcessingResult(
                outputURL: outputURL,
                inputSize: inputSizePerPage,
                outputSize: outputSize
            ))
        }

        return results
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/WordProcessorTests 2>&1 | grep -E "(Test Case|Executed)" | tail -5`

Expected: 测试通过

- [ ] **Step 5: Commit**

```bash
git add MiddleOut/Core/WordProcessor.swift MiddleOutTests/WordProcessorTests.swift
git commit -m "feat: add WordProcessor with NSAttributedString + Core Text pagination"
```

---

## Task 8: PPTProcessor — PPTXKit 渲染

**Files:**
- Create: `MiddleOut/Core/PPTProcessor.swift`
- Create: `MiddleOutTests/PPTProcessorTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `MiddleOutTests/PPTProcessorTests.swift`：

```swift
import XCTest
@testable import MiddleOut

final class PPTProcessorTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PPTTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInvalidFile_throws() {
        let fakeFile = tempDir.appendingPathComponent("fake.pptx")
        try! "not a pptx".data(using: .utf8)!.write(to: fakeFile)

        XCTAssertThrowsError(try PPTProcessor.process(at: fakeFile, quality: 0.8)) { error in
            guard case PPTProcessorError.invalidFile = error else {
                XCTFail("Expected invalidFile, got \(error)")
                return
            }
        }
    }

    // Note: Full integration test requires a real .pptx test resource.
    // Add a small test.pptx to MiddleOutTests/Resources/ for comprehensive testing.
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/PPTProcessorTests 2>&1 | grep -E "(error:|FAIL)" | head -5`

Expected: 编译失败

- [ ] **Step 3: 实现 PPTProcessor**

创建 `MiddleOut/Core/PPTProcessor.swift`：

```swift
// PPTProcessor.swift
// Converts PowerPoint .pptx files to JPEG images using PPTXKit.
// Each slide is rendered as a separate JPEG at 2x resolution.

import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import PPTXKit

enum PPTProcessorError: Error, LocalizedError {
    case invalidFile
    case emptyPresentation
    case slideRenderFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "corrupted or invalid PowerPoint file"
        case .emptyPresentation: return "presentation has no slides"
        case .slideRenderFailed(let i): return "failed to render slide \(i + 1)"
        }
    }
}

struct PPTProcessor {

    private static let scale: CGFloat = 2.0

    /// Process a .pptx file: render each slide as a JPEG.
    static func process(at url: URL, quality: Double) throws -> [ProcessingResult] {
        // Open with PPTXKit
        let presentation: PPTXPresentation
        do {
            presentation = try PPTXPresentation(url: url)
        } catch {
            throw PPTProcessorError.invalidFile
        }

        let slideCount = presentation.slides.count
        guard slideCount > 0 else {
            throw PPTProcessorError.emptyPresentation
        }

        let fm = FileManager.default
        let inputSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let inputSizePerSlide = inputSize / UInt64(max(1, slideCount))

        // Create output folder
        let folderURL = OutputNamer.docOutputFolderURL(for: url)
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var results: [ProcessingResult] = []

        for (index, slide) in presentation.slides.enumerated() {
            // Render slide to image at 2x scale
            let slideSize = presentation.slideSize
            let pixelWidth = Int(slideSize.width * scale)
            let pixelHeight = Int(slideSize.height * scale)

            guard let image = slide.renderToImage(
                size: CGSize(width: pixelWidth, height: pixelHeight)
            ) else {
                DebugLog.log("WARNING: failed to render slide \(index + 1)")
                continue  // skip this slide, continue with others
            }

            let outputURL = OutputNamer.docPageURL(for: url, pageIndex: index)

            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }

            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1, nil
            ) else {
                continue
            }

            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

            guard CGImageDestinationFinalize(destination) else {
                continue
            }

            let outputSize = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            results.append(ProcessingResult(
                outputURL: outputURL,
                inputSize: inputSizePerSlide,
                outputSize: outputSize
            ))
        }

        if results.isEmpty && slideCount > 0 {
            throw PPTProcessorError.slideRenderFailed(0)
        }

        return results
    }
}
```

**重要说明**：PPTXKit 的实际 API（`PPTXPresentation`、`slide.renderToImage`、`presentation.slideSize` 等）需要在添加 SPM 依赖后根据实际库的 API 进行调整。以上代码展示了预期的调用模式。实现时需要先 `import PPTXKit`，查看库的公开 API，然后适配。

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' -only-testing:MiddleOutTests/PPTProcessorTests 2>&1 | grep -E "(Test Case|Executed)" | tail -5`

Expected: 测试通过

- [ ] **Step 5: Commit**

```bash
git add MiddleOut/Core/PPTProcessor.swift MiddleOutTests/PPTProcessorTests.swift
git commit -m "feat: add PPTProcessor with PPTXKit slide rendering"
```

---

## Task 9: ProcessingCoordinator 集成 — 新增 Dispatch 分支

**Files:**
- Modify: `MiddleOut/Core/ProcessingCoordinator.swift`

- [ ] **Step 1: 修改 ProcessingSummary 添加 totalOutputImages**

在 `MiddleOut/Core/ProcessingCoordinator.swift` 中，修改 `ProcessingSummary` 结构体：

```swift
/// Final summary data
struct ProcessingSummary {
    let convertedCount: Int
    let totalOutputImages: Int
    let skippedFiles: [(name: String, reason: String)]
    let totalBytesSaved: Int64
}
```

- [ ] **Step 2: 修改 processOnBackground 的分类和 dispatch 逻辑**

将 `processOnBackground()` 方法中的文件分类和处理循环替换为：

```swift
        // Classify files
        let classified = FileRouter.classify(urls)
        let allProcessable = classified.images + classified.pdfs
            + classified.words + classified.excels
            + classified.ppts + classified.markdowns
        var allSkipped = classified.skipped.map { ($0.url.lastPathComponent, $0.reason) }

        guard !allProcessable.isEmpty else {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.onCompleted?(ProcessingSummary(
                    convertedCount: 0,
                    totalOutputImages: 0,
                    skippedFiles: allSkipped,
                    totalBytesSaved: 0
                ))
                SoundPlayer.playError()
            }
            return
        }

        let totalCount = allProcessable.count
        let quality = SettingsStore.shared.jpegQuality
        DebugLog.log("Processing \(totalCount) files at quality \(quality)")

        var convertedCount = 0
        var totalOutputImages = 0
        var totalBytesSaved: Int64 = 0

        for (index, url) in allProcessable.enumerated() {
            let fileName = url.lastPathComponent
            let currentBytesSaved = totalBytesSaved

            DispatchQueue.main.async {
                self.onProgress?(ProcessingProgress(
                    currentFile: fileName,
                    currentIndex: index,
                    totalCount: totalCount,
                    bytesSaved: currentBytesSaved
                ))
            }

            do {
                guard let category = FileRouter.identifyCategory(url) else {
                    allSkipped.append((fileName, "unsupported format"))
                    continue
                }

                switch category {
                case .image:
                    DebugLog.log("Processing image: \(fileName)")
                    let result = try ImageProcessor.process(at: url, quality: quality)
                    totalBytesSaved += result.bytesSaved
                    totalOutputImages += 1
                    convertedCount += 1

                case .pdf:
                    DebugLog.log("Processing PDF: \(fileName)")
                    let results = try PDFProcessor.process(at: url, quality: quality)
                    for result in results { totalBytesSaved += result.bytesSaved }
                    totalOutputImages += results.count
                    convertedCount += 1

                case .word:
                    DebugLog.log("Processing Word: \(fileName)")
                    let results = try WordProcessor.process(at: url, quality: quality)
                    for result in results { totalBytesSaved += result.bytesSaved }
                    totalOutputImages += results.count
                    convertedCount += 1

                case .excel:
                    DebugLog.log("Processing Excel: \(fileName)")
                    let results = try ExcelProcessor.process(at: url, quality: quality)
                    for result in results { totalBytesSaved += result.bytesSaved }
                    totalOutputImages += results.count
                    convertedCount += 1

                case .ppt:
                    DebugLog.log("Processing PPT: \(fileName)")
                    let results = try PPTProcessor.process(at: url, quality: quality)
                    for result in results { totalBytesSaved += result.bytesSaved }
                    totalOutputImages += results.count
                    convertedCount += 1

                case .markdown:
                    DebugLog.log("Processing Markdown: \(fileName)")
                    let results = try MarkdownProcessor.process(at: url, quality: quality)
                    for result in results { totalBytesSaved += result.bytesSaved }
                    totalOutputImages += results.count
                    convertedCount += 1
                }
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DebugLog.log("ERROR processing \(fileName): \(reason)")
                allSkipped.append((fileName, reason))
            }
        }

        let summary = ProcessingSummary(
            convertedCount: convertedCount,
            totalOutputImages: totalOutputImages,
            skippedFiles: allSkipped,
            totalBytesSaved: totalBytesSaved
        )

        DebugLog.log("Processing complete: \(convertedCount) converted, \(totalOutputImages) images, \(allSkipped.count) skipped")

        DispatchQueue.main.async {
            self.isProcessing = false
            self.onCompleted?(summary)
            SoundPlayer.playComplete()
        }
```

- [ ] **Step 3: 更新 ProgressViewController 适配新的 ProcessingSummary**

在 `MiddleOut/Panel/ProgressViewController.swift` 的 `showCompleted` 方法中，因为 `ProcessingSummary` 新增了 `totalOutputImages` 字段，需要更新构造点。找到所有创建 `ProcessingSummary` 的地方，确保传入 `totalOutputImages` 参数。

`ProgressViewController.showCompleted` 方法本身只读取 `summary` 的字段，只要编译通过就行。可选：在完成信息中显示图片数量，修改 `showCompleted` 中的 subtitle：

```swift
// 在 showCompleted 中，修改 subtitle 显示：
subtitleLabel.stringValue = "\(summary.convertedCount) files → \(summary.totalOutputImages) images"
```

- [ ] **Step 4: 构建验证通过**

Run: `xcodebuild build -project MiddleOut.xcodeproj -scheme MiddleOut -configuration Debug 2>&1 | tail -3`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 运行所有测试确认无回归**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' 2>&1 | grep "Executed"`

Expected: 所有测试通过，无失败

- [ ] **Step 6: Commit**

```bash
git add MiddleOut/Core/ProcessingCoordinator.swift MiddleOut/Panel/ProgressViewController.swift
git commit -m "feat: integrate all V2 processors into ProcessingCoordinator dispatch"
```

---

## Task 10: 端到端验证与清理

**Files:**
- All new files (review pass)
- README.md (update supported formats table)

- [ ] **Step 1: 运行全部测试**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' 2>&1 | grep -E "(Test Suite|Executed|FAIL)"`

Expected: 所有 test suite 通过，0 failures

- [ ] **Step 2: 构建 Release 版本验证**

Run: `xcodebuild -project MiddleOut.xcodeproj -scheme MiddleOut -configuration Release build 2>&1 | tail -3`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 更新 README.md 支持格式表**

在 `README.md` 的 `## Supported Formats` 表格中添加新格式，并将 `## Roadmap` 中已实现的格式标记为 Done：

Supported Formats 表格新增行：

```markdown
| Word (.docx) | JPG (per page) | Each page rendered as a separate image |
| Excel (.xlsx) | JPG (per sheet) | Each worksheet rendered as a separate image |
| PowerPoint (.pptx) | JPG (per slide) | Each slide rendered as a separate image |
| Markdown (.md) | JPG | Single or multi-page (9:16 ratio, 2K resolution) |
```

Roadmap 表格更新：

```markdown
| Word (.docx) | ✅ Done |
| Excel (.xlsx) | ✅ Done |
| PowerPoint (.pptx) | ✅ Done |
| Markdown (.md) | ✅ Done |
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update README with V2 supported formats"
```

- [ ] **Step 5: 最终全量测试**

Run: `xcodebuild test -project MiddleOut.xcodeproj -scheme MiddleOut -destination 'platform=macOS' 2>&1 | grep "Executed"`

Expected: 所有测试通过
