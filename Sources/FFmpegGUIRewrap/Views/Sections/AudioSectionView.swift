import SwiftUI

struct AudioSectionView: View {
    @Binding var settings: JobSettings
    let mediaFile: MediaFile

    var body: some View {
        Section("Audio Tracks") {
            if settings.audioTracks.isEmpty {
                Text("No audio tracks detected")
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                ForEach($settings.audioTracks) { $track in
                    AudioTrackRow(track: $track, mediaFile: mediaFile)
                }
            }
        }
    }
}

struct AudioTrackRow: View {
    @Binding var track: AudioTrackSettings
    let mediaFile: MediaFile
    @State private var isExpanded = false

    private var streamLabel: String {
        let s = mediaFile.probeData?.streams.first(where: { $0.index == track.id })
        let codec = s?.codecName?.uppercased() ?? "Audio"
        let layout = s?.channelLayout ?? s?.channels.map { "\($0)ch" } ?? ""
        let lang = s?.tags?["language"] ?? ""
        return "Stream \(track.id): \(codec) \(layout) \(lang)".trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Language").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    TextField("ISO 639-2 (e.g. eng)", text: Binding(
                        get: { track.language ?? "" },
                        set: { track.language = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                }
                GridRow {
                    Text("Title").foregroundStyle(.secondary)
                    TextField("Track title", text: Binding(
                        get: { track.title ?? "" },
                        set: { track.title = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                }
                GridRow {
                    Text("Channel Layout").foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { track.channelLayout },
                        set: { track.channelLayout = $0 }
                    )) {
                        Text("Preserve").tag(Optional<ChannelLayout>.none)
                        ForEach(ChannelLayout.allCases) { layout in
                            Text(layout.displayName).tag(Optional(layout))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                GridRow {
                    Text("Dialnorm").foregroundStyle(.secondary)
                    HStack {
                        Picker("", selection: Binding(
                            get: { track.dialnorm != nil },
                            set: { if !$0 { track.dialnorm = nil } else { track.dialnorm = -24 } }
                        )) {
                            Text("Preserve").tag(false)
                            Text("Set").tag(true)
                        }
                        .labelsHidden()
                        .frame(width: 100)

                        if track.dialnorm != nil {
                            Stepper(
                                value: Binding(
                                    get: { track.dialnorm ?? -24 },
                                    set: { track.dialnorm = $0 }
                                ),
                                in: -31...0
                            ) {
                                Text("\(track.dialnorm ?? -24) dB")
                                    .monospacedDigit()
                                    .frame(width: 60)
                            }
                        }
                    }
                }
                GridRow {
                    Text("Disposition").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        DispositionToggle(label: "Default",  value: $track.isDefault)
                        DispositionToggle(label: "Forced",   value: $track.isForced)
                        DispositionToggle(label: "HI",       value: $track.isHearingImpaired)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, 8)
        } label: {
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                Text(streamLabel)
                    .font(.callout)
                Spacer()
            }
        }
    }
}

struct DispositionToggle: View {
    let label: String
    @Binding var value: Bool?

    var body: some View {
        Button {
            switch value {
            case nil:   value = true
            case true:  value = false
            case false: value = nil
            default:    value = nil
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch value {
        case true:  return "checkmark.circle.fill"
        case false: return "xmark.circle.fill"
        default:    return "circle"
        }
    }
    private var tint: Color {
        switch value {
        case true:  return .green
        case false: return .red
        default:    return .secondary
        }
    }
}
