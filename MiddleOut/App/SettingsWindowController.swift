// SettingsWindowController.swift
// Manages the NSWindow that hosts the SwiftUI SettingsView.
// Closing the window hides it instead of destroying it.

import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController, NSWindowDelegate {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MiddleOut Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Text("Settings placeholder"))

        self.init(window: window)
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        // Just hide — app continues running in background
    }
}
