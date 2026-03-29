// SettingsView.swift
// Main settings view with General and About tabs.
// Hosted inside SettingsWindowController's NSWindow.

import SwiftUI

struct SettingsView: View {

    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 350)
    }
}
