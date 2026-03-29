// GeneralTab.swift
// Settings General tab: hotkey binding, JPEG quality, launch at login, quit button.

import SwiftUI
import KeyboardShortcuts

struct GeneralTab: View {

    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Global Shortcut
            VStack(alignment: .leading, spacing: 8) {
                Text("Global Shortcut")
                    .font(.headline)
                KeyboardShortcuts.Recorder("", name: .processFiles)
            }

            // JPEG Quality
            QualityControl(quality: $store.jpegQuality)

            // Launch at Login
            Toggle("Launch at Login", isOn: $store.launchAtLogin)

            Spacer()

            // Quit button
            Divider()
            Button("Quit MiddleOut") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundColor(.red)
        }
        .padding(20)
        .frame(width: 360)
    }
}
