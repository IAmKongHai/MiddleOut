// ProgressPanel.swift
// Floating NSPanel that shows processing progress.
// Appears at screen top-center, auto-dismisses after completion.

import AppKit

class ProgressPanel {

    static let shared = ProgressPanel()

    private var panel: NSPanel?
    private var viewController: ProgressViewController?
    private var dismissTimer: Timer?

    private init() {}

    /// Show the panel and prepare for progress updates
    func show() {
        dismissTimer?.invalidate()

        if panel == nil {
            let vc = ProgressViewController()
            vc.loadView()

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.contentViewController = vc
            panel.backgroundColor = .windowBackgroundColor

            self.panel = panel
            self.viewController = vc
        }

        viewController?.reset()

        // Position at top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 180  // 360 / 2
            let y = screenFrame.maxY - 180   // near top with some margin
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel?.orderFront(nil)
    }

    /// Update progress display
    func update(_ progress: ProcessingProgress) {
        viewController?.updateProgress(progress)
    }

    /// Show completion summary, then auto-dismiss after 2 seconds
    func showCompleted(_ summary: ProcessingSummary) {
        viewController?.showCompleted(summary)

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// Dismiss the panel
    func dismiss() {
        dismissTimer?.invalidate()
        panel?.orderOut(nil)
    }
}
