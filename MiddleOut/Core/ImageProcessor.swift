// ImageProcessor.swift
// Converts supported image formats to compressed JPEG using ImageIO.
// Validates file content via CGImageSource before processing.

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessorError: Error, LocalizedError {
    case invalidImage
    case cannotCreateDestination
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "corrupted or mismatched format"
        case .cannotCreateDestination: return "cannot create output file"
        case .writeFailed: return "cannot write output"
        }
    }
}

struct ProcessingResult {
    let outputURL: URL
    let inputSize: UInt64
    let outputSize: UInt64
    var bytesSaved: Int64 { Int64(inputSize) - Int64(outputSize) }
}

struct ImageProcessor {

    /// Convert an image file to compressed JPEG.
    /// Validates the file content before processing — throws if content is not a valid image.
    static func process(at url: URL, quality: Double) throws -> ProcessingResult {
        // Validate: try to create an image source from the file
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageProcessorError.invalidImage
        }

        let outputURL = OutputNamer.imageOutputURL(for: url)

        // Create JPEG destination
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageProcessorError.cannotCreateDestination
        }

        // Set compression quality
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessorError.writeFailed
        }

        // Calculate sizes
        let fm = FileManager.default
        let inputSize = (try fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let outputSize = (try fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0

        return ProcessingResult(outputURL: outputURL, inputSize: inputSize, outputSize: outputSize)
    }
}
