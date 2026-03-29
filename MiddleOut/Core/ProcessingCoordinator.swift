// ProcessingCoordinator.swift
// Orchestrates the full processing pipeline:
// Finder selection -> FileRouter -> Processors -> Progress updates -> Sound
// All processing runs on a background queue; UI updates dispatch to main.

import AppKit

/// Progress callback data
struct ProcessingProgress {
    let currentFile: String
    let currentIndex: Int
    let totalCount: Int
    let bytesSaved: Int64
}

/// Final summary data
struct ProcessingSummary {
    let convertedCount: Int
    let skippedFiles: [(name: String, reason: String)]
    let totalBytesSaved: Int64
}

class ProcessingCoordinator {

    static let shared = ProcessingCoordinator()

    private let queue = DispatchQueue(label: "com.middleout.processing", qos: .userInitiated)
    private(set) var isProcessing = false

    /// Callbacks for UI updates (called on main thread)
    var onProgress: ((ProcessingProgress) -> Void)?
    var onCompleted: ((ProcessingSummary) -> Void)?
    var onError: ((String) -> Void)?

    private init() {}

    /// Start processing: get Finder selection and process all supported files.
    /// Entire pipeline runs on a background queue to keep the main thread free for UI.
    func start() {
        guard !isProcessing else { return }
        isProcessing = true

        DebugLog.log("coordinator.start() — dispatching to background queue")

        queue.async { [weak self] in
            guard let self else { return }
            self.processOnBackground()
        }
    }

    /// Background processing pipeline
    private func processOnBackground() {
        DebugLog.log("processOnBackground() started")

        // Get Finder selection (AppleScript runs on background thread)
        let urls: [URL]
        do {
            urls = try FinderBridge.getSelection()
            DebugLog.log("Finder selection: \(urls.count) files")
        } catch FinderBridgeError.permissionDenied {
            DebugLog.log("ERROR: Finder Automation permission denied")
            DispatchQueue.main.async {
                self.isProcessing = false
                self.showPermissionAlert()
            }
            return
        } catch {
            DebugLog.log("ERROR: FinderBridge failed: \(error)")
            DispatchQueue.main.async {
                self.isProcessing = false
                SoundPlayer.playError()
            }
            return
        }

        guard !urls.isEmpty else {
            DebugLog.log("No files selected in Finder")
            DispatchQueue.main.async {
                self.isProcessing = false
                SoundPlayer.playError()
            }
            return
        }

        // Classify files
        let classified = FileRouter.classify(urls)
        let allProcessable = classified.images + classified.pdfs
        var allSkipped = classified.skipped.map { ($0.url.lastPathComponent, $0.reason) }

        guard !allProcessable.isEmpty else {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.onCompleted?(ProcessingSummary(
                    convertedCount: 0,
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
        var totalBytesSaved: Int64 = 0

        for (index, url) in allProcessable.enumerated() {
            let fileName = url.lastPathComponent
            let currentBytesSaved = totalBytesSaved

            // Send progress update to main thread (async — don't block background processing)
            DispatchQueue.main.async {
                self.onProgress?(ProcessingProgress(
                    currentFile: fileName,
                    currentIndex: index,
                    totalCount: totalCount,
                    bytesSaved: currentBytesSaved
                ))
            }

            let ext = url.pathExtension.lowercased()
            let isPDF = (ext == "pdf")

            do {
                if isPDF {
                    DebugLog.log("Processing PDF: \(fileName)")
                    let results = try PDFProcessor.process(at: url, quality: quality)
                    for result in results {
                        totalBytesSaved += result.bytesSaved
                    }
                    convertedCount += 1
                } else {
                    DebugLog.log("Processing image: \(fileName)")
                    let result = try ImageProcessor.process(at: url, quality: quality)
                    totalBytesSaved += result.bytesSaved
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
            skippedFiles: allSkipped,
            totalBytesSaved: totalBytesSaved
        )

        DebugLog.log("Processing complete: \(convertedCount) converted, \(allSkipped.count) skipped")

        DispatchQueue.main.async {
            self.isProcessing = false
            self.onCompleted?(summary)
            SoundPlayer.playComplete()
        }
    }

    /// Show a one-time alert for Automation permission
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "MiddleOut Needs Permission"
        alert.informativeText = "MiddleOut needs Automation permission for Finder to read your file selection. Please grant access in System Settings > Privacy & Security > Automation."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
        isProcessing = false
    }
}
