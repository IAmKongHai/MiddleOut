// ProgressViewController.swift
// NSViewController hosting the progress UI inside the floating panel.
// Manages the progress bar, current file label, and summary display.

import AppKit

class ProgressViewController: NSViewController {

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "MiddleOut")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let fileLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let leftStatLabel = NSTextField(labelWithString: "")
    private let rightStatLabel = NSTextField(labelWithString: "")
    private let skipLabel = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 160))
        self.view = container

        // App icon
        let iconImage = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: "MiddleOut")
        iconView.image = iconImage
        iconView.frame = NSRect(x: 16, y: 110, width: 32, height: 32)
        container.addSubview(iconView)

        // Title
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 56, y: 124, width: 280, height: 18)
        container.addSubview(titleLabel)

        // Subtitle
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 56, y: 108, width: 280, height: 16)
        container.addSubview(subtitleLabel)

        // Current file
        fileLabel.font = .systemFont(ofSize: 12)
        fileLabel.textColor = .labelColor
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.frame = NSRect(x: 16, y: 82, width: 328, height: 16)
        container.addSubview(fileLabel)

        // Progress bar
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1.0
        progressBar.frame = NSRect(x: 16, y: 62, width: 328, height: 8)
        container.addSubview(progressBar)

        // Stats
        leftStatLabel.font = .systemFont(ofSize: 11)
        leftStatLabel.textColor = .secondaryLabelColor
        leftStatLabel.frame = NSRect(x: 16, y: 42, width: 200, height: 14)
        container.addSubview(leftStatLabel)

        rightStatLabel.font = .systemFont(ofSize: 11)
        rightStatLabel.textColor = .secondaryLabelColor
        rightStatLabel.alignment = .right
        rightStatLabel.frame = NSRect(x: 144, y: 42, width: 200, height: 14)
        container.addSubview(rightStatLabel)

        // Skip label (hidden by default)
        skipLabel.font = .systemFont(ofSize: 11)
        skipLabel.textColor = .systemOrange
        skipLabel.frame = NSRect(x: 16, y: 8, width: 328, height: 30)
        skipLabel.isHidden = true
        container.addSubview(skipLabel)
    }

    func updateProgress(_ progress: ProcessingProgress) {
        subtitleLabel.stringValue = "Processing \(progress.totalCount) files..."
        fileLabel.stringValue = "Converting: \(progress.currentFile)"
        progressBar.doubleValue = Double(progress.currentIndex) / Double(progress.totalCount)
        leftStatLabel.stringValue = "\(progress.currentIndex) of \(progress.totalCount) completed"
        rightStatLabel.stringValue = "Saved \(formatBytes(progress.bytesSaved))"
    }

    func showCompleted(_ summary: ProcessingSummary) {
        let iconImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done")
        iconView.image = iconImage
        iconView.contentTintColor = .systemGreen

        titleLabel.stringValue = "Done!"
        titleLabel.textColor = .systemGreen
        subtitleLabel.stringValue = "\(summary.convertedCount + summary.skippedFiles.count) files processed"

        fileLabel.isHidden = true
        progressBar.doubleValue = 1.0

        let skippedCount = summary.skippedFiles.count
        leftStatLabel.stringValue = "\(summary.convertedCount) converted\(skippedCount > 0 ? " · \(skippedCount) skipped" : "")"
        rightStatLabel.stringValue = "Total saved: \(formatBytes(summary.totalBytesSaved))"

        if !summary.skippedFiles.isEmpty {
            let names = summary.skippedFiles.map { "\($0.name) (\($0.reason))" }.joined(separator: ", ")
            skipLabel.stringValue = "Skipped: \(names)"
            skipLabel.isHidden = false
        }
    }

    /// Reset to initial state for reuse
    func reset() {
        let iconImage = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: "MiddleOut")
        iconView.image = iconImage
        iconView.contentTintColor = .labelColor
        titleLabel.stringValue = "MiddleOut"
        titleLabel.textColor = .labelColor
        subtitleLabel.stringValue = ""
        fileLabel.stringValue = ""
        fileLabel.isHidden = false
        progressBar.doubleValue = 0
        leftStatLabel.stringValue = ""
        rightStatLabel.stringValue = ""
        skipLabel.isHidden = true
        skipLabel.stringValue = ""
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
