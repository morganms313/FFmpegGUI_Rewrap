import SwiftUI

struct AFDSectionView: View {
    @Binding var settings: JobSettings

    var body: some View {
        Section {
            Picker("AFD Mode", selection: $settings.afdMode) {
                ForEach(AFDMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if settings.afdMode == .set {
                afdCodePicker
                afdDiagram
                barDataSection
            }

        } header: {
            Text("Active Format Description")
        } footer: {
            if settings.afdMode == .set {
                Text("AFD injection requires a render pass (video filter). AFD removal uses a bitstream filter (no re-encode).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var afdCodePicker: some View {
        Picker("AFD Code", selection: $settings.afdCode) {
            ForEach(AFDCode.all) { code in
                Text("\(code.value) — \(code.description)").tag(code.value)
            }
        }
    }

    @ViewBuilder
    private var afdDiagram: some View {
        if let code = AFDCode.all.first(where: { $0.value == settings.afdCode }) {
            HStack(spacing: 16) {
                AFDDiagramView(code: code)
                    .frame(width: 120, height: 68)

                VStack(alignment: .leading, spacing: 4) {
                    Text("AFD \(code.value)")
                        .font(.headline.monospacedDigit())
                    Text(code.description)
                        .font(.callout)
                    Text(code.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var barDataSection: some View {
        Group {
            Toggle("Include Bar Data (SMPTE 2016-3)", isOn: $settings.includeBarData)

            if settings.includeBarData {
                HStack {
                    LabeledContent("Top") {
                        IntegerField(value: $settings.barData.topBar, range: 0...1080)
                    }
                    LabeledContent("Bottom") {
                        IntegerField(value: $settings.barData.bottomBar, range: 0...1080)
                    }
                }
                HStack {
                    LabeledContent("Left") {
                        IntegerField(value: $settings.barData.leftBar, range: 0...1920)
                    }
                    LabeledContent("Right") {
                        IntegerField(value: $settings.barData.rightBar, range: 0...1920)
                    }
                }
                Text("Lines (top/bottom) and pixels (left/right) of pillarbox/letterbox bars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - AFD Codes

struct AFDCode: Identifiable {
    let value: Int
    let description: String
    let detail: String
    var id: Int { value }

    static let all: [AFDCode] = [
        AFDCode(value: 0,  description: "Undefined",               detail: "Not defined"),
        AFDCode(value: 2,  description: "4:3",                     detail: "Box 4:3, top of 16:9 frame"),
        AFDCode(value: 3,  description: "14:9 (letterbox)",        detail: "Box 14:9, top of 16:9"),
        AFDCode(value: 4,  description: "Full frame (>16:9)",      detail: "Full width, 16:9+ frame"),
        AFDCode(value: 8,  description: "Full frame 4:3 or 16:9",  detail: "Full frame, aspect per WSS/coding"),
        AFDCode(value: 9,  description: "4:3 pillarbox in 16:9",   detail: "4:3 center of 16:9 frame"),
        AFDCode(value: 10, description: "16:9 letterbox in 4:3",   detail: "16:9 center of 4:3 frame"),
        AFDCode(value: 11, description: "14:9 in 4:3 or 16:9",     detail: "14:9 center"),
        AFDCode(value: 13, description: "4:3 with shoot&protect",  detail: "4:3 with 14:9 protect area"),
        AFDCode(value: 14, description: "16:9 with shoot&protect", detail: "16:9 with 14:9 protect area"),
        AFDCode(value: 15, description: "16:9 with 4:3 protect",   detail: "16:9 with 4:3 protect area"),
    ]
}

// MARK: - AFD visual diagram

struct AFDDiagramView: View {
    let code: AFDCode

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Outer frame (transmission frame)
                Rectangle()
                    .stroke(Color.secondary, lineWidth: 1)
                    .frame(width: geo.size.width, height: geo.size.height)

                // Active picture area (simplified representation)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: activeWidth(geo), height: activeHeight(geo))
                    .offset(x: 0, y: 0)

                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: activeWidth(geo), height: activeHeight(geo))

                // Code label
                Text("AFD \(code.value)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(3)
            }
        }
        .background(Color.primary.opacity(0.05))
        .cornerRadius(4)
    }

    /// Simplified: use code to pick approximate active box
    private func activeWidth(_ geo: GeometryProxy) -> CGFloat {
        switch code.value {
        case 9:  return geo.size.width * 0.75   // 4:3 in 16:9 pillarbox
        default: return geo.size.width
        }
    }
    private func activeHeight(_ geo: GeometryProxy) -> CGFloat {
        switch code.value {
        case 2:  return geo.size.height * 0.75  // 4:3 letterbox in 16:9
        case 3:  return geo.size.height * 0.875 // 14:9
        case 10: return geo.size.height * 0.75  // 16:9 in 4:3
        default: return geo.size.height
        }
    }
}
