// HotkeyManager.swift
// Registers a global keyboard shortcut and fires a callback when pressed.
// Uses KeyboardShortcuts library for Mac App Store-compatible hotkey handling.

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let processFiles = Self(
        "processFiles",
        default: KeyboardShortcuts.Shortcut(.j, modifiers: [.control, .option])
    )
}

class HotkeyManager {

    static let shared = HotkeyManager()
    var onHotkeyPressed: (() -> Void)?

    private init() {}

    /// Start listening for the global hotkey
    func start() {
        KeyboardShortcuts.onKeyUp(for: .processFiles) { [weak self] in
            self?.onHotkeyPressed?()
        }
    }
}
