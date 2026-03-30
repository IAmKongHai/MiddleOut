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

    // A4 page dimensions in points
    private static let pageWidthPt: CGFloat = 595
    private static let pageHeightPt: CGFloat = 842
    // Render at 2x scale for crisp output: 1190×1684 pixels
    private static let scale: CGFloat = 2.0
    // Page margin in points
    private static let marginPt: CGFloat = 50

    /// Convert a .docx file to one or more JPEG page images.
    /// Returns a ProcessingResult for each rendered page.
    static func process(at url: URL, quality: Double) throws -> [ProcessingResult] {
        DebugLog.log("WordProcessor: loading \(url.lastPathComponent)")

        // Load .docx via NSAttributedString — auto-detect format with empty options
        let attributedString: NSAttributedString
        do {
            attributedString = try NSAttributedString(
                url: url,
                options: [:],
                documentAttributes: nil
            )
        } catch {
            DebugLog.log("WordProcessor: failed to load document — \(error.localizedDescription)")
            throw WordProcessorError.invalidDocument
        }

        guard attributedString.length > 0 else {
            throw WordProcessorError.emptyDocument
        }

        // Paginate using Core Text CTFramesetter
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
            if visibleRange.length == 0 { break }

            pages.append(visibleRange)
            currentIndex += visibleRange.length
        }

        guard !pages.isEmpty else {
            throw WordProcessorError.emptyDocument
        }

        DebugLog.log("WordProcessor: paginated into \(pages.count) page(s)")

        let fm = FileManager.default
        let inputSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let inputSizePerPage = inputSize / UInt64(max(1, pages.count))

        // Create output folder
        let folderURL = OutputNamer.docOutputFolderURL(for: url)
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var results: [ProcessingResult] = []

        for (pageIndex, pageRange) in pages.enumerated() {
            let cgImage = try renderPage(framesetter: framesetter, range: pageRange, pageIndex: pageIndex)
            let outputURL = OutputNamer.docPageURL(for: url, pageIndex: pageIndex)
            try writeJPEG(cgImage: cgImage, to: outputURL, quality: quality, pageIndex: pageIndex)

            let outputSize = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            results.append(ProcessingResult(
                outputURL: outputURL,
                inputSize: inputSizePerPage,
                outputSize: outputSize
            ))
        }

        DebugLog.log("WordProcessor: completed \(results.count) page(s) for \(url.lastPathComponent)")
        return results
    }

    // MARK: - Private Helpers

    /// Render a single page of text into a CGImage at 2x scale.
    private static func renderPage(framesetter: CTFramesetter, range: CFRange, pageIndex: Int) throws -> CGImage {
        let pixelWidth = Int(pageWidthPt * scale)
        let pixelHeight = Int(pageHeightPt * scale)
        let textWidth = pageWidthPt - (marginPt * 2)
        let textHeight = pageHeightPt - (marginPt * 2)

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
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // Scale for 2x rendering
        context.scaleBy(x: scale, y: scale)

        // Translate to apply margins (Core Text origin is bottom-left, matching CGContext)
        context.translateBy(x: marginPt, y: marginPt)

        // Create and draw the frame for this page range
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: textWidth, height: textHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
        CTFrameDraw(frame, context)

        guard let cgImage = context.makeImage() else {
            throw WordProcessorError.renderFailed(pageIndex)
        }

        return cgImage
    }

    /// Write a CGImage to a JPEG file using CGImageDestination.
    private static func writeJPEG(cgImage: CGImage, to url: URL, quality: Double, pageIndex: Int) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw WordProcessorError.renderFailed(pageIndex)
        }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw WordProcessorError.renderFailed(pageIndex)
        }
    }
}
