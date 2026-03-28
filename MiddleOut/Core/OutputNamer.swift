// OutputNamer.swift
// Generates unique output file names for processed files.
// Handles image _opt.jpg naming, PDF folder/page naming, and conflict resolution.

import Foundation

struct OutputNamer {

    /// Generate output URL for an image: same directory, `name_opt.jpg`
    static func imageOutputURL(for input: URL) -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let dir = input.deletingLastPathComponent()
        let output = dir.appendingPathComponent("\(name)_opt.jpg")
        return uniqueURL(for: output)
    }

    /// Generate the output folder URL for a PDF: same directory, `name_pages/`
    static func pdfOutputFolderURL(for input: URL) -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let dir = input.deletingLastPathComponent()
        return dir.appendingPathComponent("\(name)_pages")
    }

    /// Generate a page URL inside the PDF output folder: `name_page_N.jpg`
    static func pdfPageURL(for input: URL, pageIndex: Int) -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let folder = pdfOutputFolderURL(for: input)
        return folder.appendingPathComponent("\(name)_page_\(pageIndex + 1).jpg")
    }

    /// If a file already exists at the URL, append an incrementing number.
    /// `photo_opt.jpg` -> `photo_opt_2.jpg` -> `photo_opt_3.jpg`
    static func uniqueURL(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }

        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent

        var counter = 2
        while true {
            let candidate = dir.appendingPathComponent("\(baseName)_\(counter).\(ext)")
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
