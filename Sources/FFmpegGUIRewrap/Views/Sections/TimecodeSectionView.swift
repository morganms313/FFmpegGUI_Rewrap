import SwiftUI

struct TimecodeSectionView: View {
    @Binding var settings: JobSettings

    var body: some View {
        Section("Timecode") {
            sectionContent
        }
    }

    // Factored into a typed @ViewBuilder property so the Section
    // type-checker sees `some View`, not an ambiguous multi-expression closure.
    @ViewBuilder
    private var sectionContent: some View {
        Picker("Mode", selection: $settings.timecodeMode) {
            ForEach(TimecodeMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        if settings.timecodeMode == .set {
            setModeContent
        }
    }

    @ViewBuilder
    private var setModeContent: some View {
        HStack {
            Text("Start TC")
                .foregroundStyle(.secondary)
            TextField("HH:MM:SS:FF", text: $settings.timecodeStart)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
                .onChange(of: settings.timecodeStart) {
                    settings.timecodeStart = formatTimecode(settings.timecodeStart)
                }
        }

        Toggle("Drop Frame (;)", isOn: $settings.timecodeDropFrame)
            .onChange(of: settings.timecodeDropFrame) {
                settings.timecodeStart = formatTimecode(settings.timecodeStart)
            }

        Text("Use HH:MM:SS:FF (non-drop) or HH:MM:SS;FF (drop). Drop frame applies to 29.97 and 59.94 fps.")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack {
            Text("Presets").foregroundStyle(.secondary)
            Spacer()
            Button("01:00:00:00") { settings.timecodeStart = "01:00:00:00" }
                .buttonStyle(.plain).foregroundStyle(.tint)
            Button("00:58:30:00") { settings.timecodeStart = "00:58:30:00" }
                .buttonStyle(.plain).foregroundStyle(.tint)
            Button("10:00:00:00") { settings.timecodeStart = "10:00:00:00" }
                .buttonStyle(.plain).foregroundStyle(.tint)
        }
        .font(.callout)
    }

    private func formatTimecode(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        guard digits.count >= 8 else { return raw }
        let s = String(digits.prefix(8))
        let sep = settings.timecodeDropFrame ? ";" : ":"
        let hh = String(s.prefix(2))
        let mm = String(s.dropFirst(2).prefix(2))
        let ss = String(s.dropFirst(4).prefix(2))
        let ff = String(s.dropFirst(6).prefix(2))
        return "\(hh):\(mm):\(ss)\(sep)\(ff)"
    }
}
