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
        DebugLog.log("ProgressPanel.show() called, panel==nil: \(panel == nil)")
        dismissTimer?.invalidate()

        if panel == nil {
            DebugLog.log("Creating new NSPanel and ProgressViewController")
            let vc = ProgressViewController()
            vc.loadView()
            DebugLog.log("vc.loadView() done, view frame: \(vc.view.frame)")

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
            DebugLog.log("NSPanel created, frame: \(panel.frame)")
        }

        viewController?.reset()

        // Position at top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 180  // 360 / 2
            let y = screenFrame.maxY - 180   // near top with some margin
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
            DebugLog.log("Panel positioned at x:\(x), y:\(y), screen: \(screenFrame)")
        } else {
            DebugLog.log("WARNING: NSScreen.main is nil!")
        }

        // For accessory apps (.accessory activation policy), we must temporarily
        // activate the app to bring the panel to front, then set it back.
        // Also set the panel to .floating + canHide=false to keep it visible.
        panel?.hidesOnDeactivate = false
        panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        panel?.displayIfNeeded()
        DebugLog.log("panel.makeKeyAndOrderFront called, isVisible: \(panel?.isVisible ?? false), frame: \(panel?.frame ?? .zero)")
    }

    /// Update progress display
    func update(_ progress: ProcessingProgress) {
        DebugLog.log("ProgressPanel.update() \(progress.currentIndex)/\(progress.totalCount)")
        viewController?.updateProgress(progress)
    }

    /// Show completion summary, then auto-dismiss after 2 seconds
    func showCompleted(_ summary: ProcessingSummary) {
        DebugLog.log("ProgressPanel.showCompleted() converted:\(summary.convertedCount)")
        viewController?.showCompleted(summary)

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            DebugLog.log("Dismiss timer fired")
            self?.dismiss()
        }
    }

    /// Dismiss the panel
    func dismiss() {
        DebugLog.log("ProgressPanel.dismiss()")
        dismissTimer?.invalidate()
        panel?.orderOut(nil)
    }
}
