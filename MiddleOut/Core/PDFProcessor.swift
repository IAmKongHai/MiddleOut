// PDFProcessor.swift
// Extracts each page from a PDF and renders it as a compressed JPEG.
// Uses PDFKit for rendering and ImageIO for JPEG output.

import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

enum PDFProcessorError: Error, LocalizedError {
    case invalidPDF
    case pageRenderFailed(Int)
    case cannotCreateDestination(Int)
    case writeFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "corrupted or mismatched format"
        case .pageRenderFailed(let i): return "failed to render page \(i + 1)"
        case .cannotCreateDestination(let i): return "cannot create output for page \(i + 1)"
        case .writeFailed(let i): return "cannot write page \(i + 1)"
        }
    }
}

struct PDFProcessor {

    /// Process a PDF file: extract each page as a JPEG image.
    /// Returns one ProcessingResult per page.
    static func process(at url: URL, quality: Double) throws -> [ProcessingResult] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw PDFProcessorError.invalidPDF
        }

        let fm = FileManager.default
        let inputSize = (try fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let inputSizePerPage = inputSize / UInt64(document.pageCount)

        // Create output folder
        let folderURL = OutputNamer.pdfOutputFolderURL(for: url)
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var results: [ProcessingResult] = []

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else {
                throw PDFProcessorError.pageRenderFailed(i)
            }

            // Render page at 2x scale for good quality (144 DPI)
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let width = Int(bounds.width * scale)
            let height = Int(bounds.height * scale)

            guard let cgImage = page.thumbnail(of: CGSize(width: width, height: height), for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw PDFProcessorError.pageRenderFailed(i)
            }

            let outputURL = OutputNamer.pdfPageURL(for: url, pageIndex: i)

            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                throw PDFProcessorError.cannotCreateDestination(i)
            }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

            guard CGImageDestinationFinalize(destination) else {
                throw PDFProcessorError.writeFailed(i)
            }

            let outputSize = (try fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            results.append(ProcessingResult(
                outputURL: outputURL,
                inputSize: inputSizePerPage,
                outputSize: outputSize
            ))
        }

        return results
    }
}
