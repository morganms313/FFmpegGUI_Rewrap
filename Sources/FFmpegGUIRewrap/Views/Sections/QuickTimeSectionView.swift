import SwiftUI

struct QuickTimeSectionView: View {
    @Binding var settings: JobSettings

    var body: some View {
        Section {
            LabeledContent("Reel Name") {
                TextField("Reel / tape name", text: Binding(
                    get: { settings.quickTimeSettings.reelName ?? "" },
                    set: { settings.quickTimeSettings.reelName = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            }

            LabeledContent("Clip Name") {
                TextField("com.apple.proapps.clipname", text: Binding(
                    get: { settings.quickTimeSettings.clipName ?? "" },
                    set: { settings.quickTimeSettings.clipName = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            }

            // ProRes profile tag (container tag only, no re-encode)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Override ProRes Profile Tag", isOn: $settings.quickTimeSettings.overrideProResProfile)
                if settings.quickTimeSettings.overrideProResProfile {
                    Picker("Profile", selection: $settings.quickTimeSettings.proResProfile) {
                        ForEach(ProResProfile.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    Text("Changes the container profile tag only — does not re-encode. Use only if the tag is incorrect.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Picker("Timecode Track", selection: $settings.quickTimeSettings.manageTmcdTrack) {
                ForEach(TmcdTrackMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Picker("Spatial Video", selection: $settings.quickTimeSettings.spatialVideoMode) {
                ForEach(SpatialVideoMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("Preserve Camera Metadata Atoms", isOn: $settings.quickTimeSettings.preserveCameraMetadata)

        } header: {
            Text("QuickTime / MOV")
        } footer: {
            Text("Camera metadata atoms (ARRI, RED, Sony, etc.) are preserved during stream copy when enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
