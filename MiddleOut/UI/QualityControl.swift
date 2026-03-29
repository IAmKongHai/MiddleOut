// QualityControl.swift
// Reusable SwiftUI component: JPEG quality slider + preset buttons.
// Clicking a preset moves the slider; dragging the slider deselects presets
// if the value doesn't match.

import SwiftUI

struct QualityControl: View {

    @Binding var quality: Double

    private let presets: [(label: String, value: Double)] = [
        ("Low 40%", 0.4),
        ("Medium 60%", 0.6),
        ("High 80%", 0.8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("JPEG Quality")
                .font(.headline)

            // Preset buttons
            HStack(spacing: 8) {
                ForEach(presets, id: \.value) { preset in
                    Button(preset.label) {
                        quality = preset.value
                    }
                    .buttonStyle(.bordered)
                    .tint(isActive(preset.value) ? .accentColor : nil)
                }
            }

            // Slider with percentage label
            HStack {
                Slider(value: $quality, in: 0...1, step: 0.01)
                Text("\(Int(quality * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private func isActive(_ value: Double) -> Bool {
        abs(quality - value) < 0.01
    }
}
