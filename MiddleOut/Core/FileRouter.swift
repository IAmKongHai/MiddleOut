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
            // File too small or empty — check extension fallback for text formats
            let ext = url.pathExtension.lowercased()
            if markdownExtensions.contains(ext) {
                return .markdown
            }
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

        let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        var eocdOffset = -1
        let bytes = Array(data)

        // Search for End of Central Directory record from end of file
        let searchStart = max(0, bytes.count - 65557)
        for i in stride(from: bytes.count - 4, through: searchStart, by: -1) {
            if bytes[i] == eocdSignature[0] && bytes[i+1] == eocdSignature[1]
                && bytes[i+2] == eocdSignature[2] && bytes[i+3] == eocdSignature[3] {
                eocdOffset = i
                break
            }
        }
        guard eocdOffset >= 0, eocdOffset + 22 <= bytes.count else { return nil }

        // Read central directory offset and entry count from EOCD
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

        // Parse central directory entries to collect file names
        var offset = cdOffset
        var fileNames: [String] = []

        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count else { break }
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

        // Identify Office format by internal directory markers
        let hasWordMarker = fileNames.contains { $0.hasPrefix("word/") }
        let hasExcelMarker = fileNames.contains { $0.hasPrefix("xl/") }
        let hasPPTMarker = fileNames.contains { $0.hasPrefix("ppt/") }

        if hasWordMarker { return .word }
        if hasExcelMarker { return .excel }
        if hasPPTMarker { return .ppt }

        return nil
    }
}
