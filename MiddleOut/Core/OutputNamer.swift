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
    /// Special characters in sheet name (/ : \ * ? " < > |) are replaced with underscore.
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
}
