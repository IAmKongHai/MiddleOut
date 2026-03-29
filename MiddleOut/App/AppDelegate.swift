// AppDelegate.swift
// Manages app lifecycle: agent mode (no Dock/MenuBar), relaunch detection,
// and settings window show/hide.

import AppKit
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {

    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Start listening for global hotkey
        HotkeyManager.shared.onHotkeyPressed = { [weak self] in
            self?.handleHotkeyPressed()
        }
        HotkeyManager.shared.start()

        showSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return false
    }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Entry point when user presses the global hotkey
    private func handleHotkeyPressed() {
        let coordinator = ProcessingCoordinator.shared
        let panel = ProgressPanel.shared

        coordinator.onProgress = { progress in
            panel.show()
            panel.update(progress)
        }

        coordinator.onCompleted = { summary in
            panel.showCompleted(summary)
        }

        coordinator.start()
    }
}
