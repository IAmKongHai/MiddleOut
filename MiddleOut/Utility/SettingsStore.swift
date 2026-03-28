// SettingsStore.swift
// Centralized persistence for user preferences using UserDefaults.
// Provides a single source of truth for all configurable settings.

import Combine
import Foundation
import ServiceManagement

class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    /// JPEG compression quality (0.0 to 1.0). Default: 0.8 (High)
    @Published var jpegQuality: Double {
        didSet { UserDefaults.standard.set(jpegQuality, forKey: "jpegQuality") }
    }

    /// Whether the app should launch at login
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert on failure
                launchAtLogin = !launchAtLogin
            }
        }
    }

    private init() {
        let defaults = UserDefaults.standard

        // Load persisted quality or use default 0.8
        if defaults.object(forKey: "jpegQuality") != nil {
            self.jpegQuality = defaults.double(forKey: "jpegQuality")
        } else {
            self.jpegQuality = 0.8
        }

        // Read current launch-at-login state from system
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
