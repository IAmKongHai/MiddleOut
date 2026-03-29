// AboutTab.swift
// Settings About tab: app icon, version, description, links, easter egg.

import SwiftUI

struct AboutTab: View {

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // App Icon (from Assets.xcassets)
            Image("AboutIcon")
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            Text("MiddleOut")
                .font(.title2.bold())

            Text("Version \(appVersion)")
                .foregroundColor(.secondary)
                .font(.caption)

            Text("A lightweight macOS tool that instantly converts and compresses images & PDFs — all triggered by a global hotkey.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)

            // Links
            VStack(spacing: 6) {
                Link("GitHub Repository →",
                     destination: URL(string: "https://github.com/IAmKongHai/MiddleOut")!)
                    .font(.caption)
                Link("Report an Issue →",
                     destination: URL(string: "https://github.com/IAmKongHai/MiddleOut/issues")!)
                    .font(.caption)
            }

            Spacer()

            // Easter egg
            Text("Inspired by the Middle-Out algorithm\nfrom HBO's Silicon Valley")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary.opacity(0.6))
                .font(.system(size: 10))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        }
        .padding(20)
        .frame(width: 360)
    }
}
