// FileRouter.swift
// Classifies files by extension and dispatches to the correct processor.
// Case-insensitive extension matching.

import Foundation

struct FileRouter {

    /// Classification result containing categorized file URLs
    struct ClassificationResult {
        let images: [URL]
        let pdfs: [URL]
        let skipped: [(url: URL, reason: String)]
    }

    /// Supported image file extensions
    private static let imageExtensions: Set<String> = ["heic", "png", "tiff", "webp", "jpg", "jpeg"]

    /// Supported PDF file extensions
    private static let pdfExtensions: Set<String> = ["pdf"]

    /// Classify a list of URLs into images, PDFs, and skipped files.
    static func classify(_ urls: [URL]) -> ClassificationResult {
        var images: [URL] = []
        var pdfs: [URL] = []
        var skipped: [(url: URL, reason: String)] = []

        for url in urls {
            let ext = url.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                images.append(url)
            } else if pdfExtensions.contains(ext) {
                pdfs.append(url)
            } else {
                skipped.append((url: url, reason: "unsupported format"))
            }
        }

        return ClassificationResult(images: images, pdfs: pdfs, skipped: skipped)
    }
}
