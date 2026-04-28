import SwiftUI

struct InspectorView: View {
    let mediaFile: MediaFile

    var body: some View {
        ScrollView {
            if let probe = mediaFile.probeData {
                VStack(alignment: .leading, spacing: 0) {
                    FormatSection(format: probe.format)
                    Divider()
                    ForEach(probe.streams) { stream in
                        StreamSection(stream: stream)
                        Divider()
                    }
                }
            } else if mediaFile.isProbing {
                HStack {
                    ProgressView()
                    Text("Probing…").foregroundStyle(.secondary)
                }
                .padding()
            } else if let err = mediaFile.probeError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .font(.callout)
    }
}

// MARK: - Format section

struct FormatSection: View {
    let format: FormatInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Container", icon: "doc.fill")
            ProbeRow("Format",    value: format.formatLongName ?? format.formatName ?? "—")
            ProbeRow("Duration",  value: format.durationFormatted ?? "—")
            ProbeRow("Size",      value: format.sizeMB ?? "—")
            ProbeRow("Bit Rate",  value: format.bitRate.map { bitrateString($0) } ?? "—")
            if let tags = format.tags, !tags.isEmpty {
                SectionHeader(title: "Container Tags", icon: "tag")
                ForEach(tags.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                    ProbeRow(kv.key, value: kv.value)
                }
            }
        }
    }
}

// MARK: - Stream section

struct StreamSection: View {
    let stream: StreamInfo

    private var typeIcon: String {
        switch stream.codecTypeEnum {
        case .video:    return "video.fill"
        case .audio:    return "waveform"
        case .data:     return "doc.text"
        case .subtitle: return "captions.bubble"
        case .unknown:  return "questionmark"
        }
    }

    private var title: String {
        let type = (stream.codecType ?? "Unknown").capitalized
        return "Stream \(stream.index) — \(type)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title, icon: typeIcon)
            ProbeRow("Codec", value: stream.codecLongName ?? stream.codecName ?? "—")

            switch stream.codecTypeEnum {
            case .video:
                videoRows
            case .audio:
                audioRows
            default:
                if let tags = stream.tags {
                    ForEach(tags.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                        ProbeRow(kv.key, value: kv.value)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var videoRows: some View {
        if let w = stream.width, let h = stream.height {
            ProbeRow("Resolution", value: "\(w) × \(h)")
        }
        if let fps = stream.rFrameRate {
            ProbeRow("Frame Rate", value: formatFPS(fps))
        }
        ProbeRow("Pixel Format",   value: stream.pixFmt ?? "—")
        ProbeRow("Color Primaries",value: stream.colorPrimaries ?? "—")
        ProbeRow("Transfer",       value: stream.colorTransfer ?? "—")
        ProbeRow("Color Matrix",   value: stream.colorSpace ?? "—")
        ProbeRow("Color Range",    value: stream.colorRange ?? "—")
        ProbeRow("Chroma Loc",     value: stream.chromaLocation ?? "—")
        ProbeRow("Field Order",    value: stream.fieldOrder ?? "—")
        if let sar = stream.sampleAspectRatio { ProbeRow("SAR", value: sar) }
        if let dar = stream.displayAspectRatio { ProbeRow("DAR", value: dar) }
        if let bps = stream.bitsPerRawSample   { ProbeRow("Bit Depth", value: bps + "-bit") }

        // HDR side data
        if let sideData = stream.sideDataList {
            ForEach(Array(sideData.enumerated()), id: \.offset) { _, item in
                if let type_ = item.sideDataType {
                    SectionHeader(title: type_, icon: "sparkles")
                    if let maxL = item.maxLuminance { ProbeRow("Max Luminance", value: maxL) }
                    if let minL = item.minLuminance { ProbeRow("Min Luminance", value: minL) }
                    if let mc  = item.maxContent    { ProbeRow("MaxCLL",  value: "\(mc) cd/m²") }
                    if let ma  = item.maxAverage    { ProbeRow("MaxFALL", value: "\(ma) cd/m²") }
                }
            }
        }

        if let tags = stream.tags, !tags.isEmpty {
            ForEach(tags.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                ProbeRow(kv.key, value: kv.value)
            }
        }
    }

    @ViewBuilder
    private var audioRows: some View {
        ProbeRow("Sample Rate",    value: stream.sampleRate.map { "\($0) Hz" } ?? "—")
        ProbeRow("Channels",       value: stream.channelLayout ?? stream.channels.map { "\($0)" } ?? "—")
        ProbeRow("Sample Format",  value: stream.sampleFmt ?? "—")
        ProbeRow("Bit Depth",      value: stream.bitsPerSample.map { "\($0)-bit" } ?? "—")
        if let tags = stream.tags {
            ProbeRow("Language",   value: tags["language"] ?? "—")
            ProbeRow("Title",      value: tags["title"] ?? tags["handler_name"] ?? "—")
        }
    }
}

// MARK: - Helpers

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

struct ProbeRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

private func bitrateString(_ raw: String) -> String {
    guard let bps = Double(raw) else { return raw }
    if bps >= 1_000_000 { return String(format: "%.1f Mbps", bps / 1_000_000) }
    if bps >= 1_000     { return String(format: "%.0f kbps", bps / 1_000) }
    return "\(raw) bps"
}

private func formatFPS(_ rational: String) -> String {
    let parts = rational.split(separator: "/")
    guard parts.count == 2,
          let num = Double(parts[0]),
          let den = Double(parts[1]),
          den > 0 else { return rational }
    let fps = num / den
    // Common broadcast frame rates
    let known: [(Double, String)] = [
        (23.976, "23.976"), (24.0, "24"), (25.0, "25"),
        (29.97, "29.97"), (30.0, "30"), (50.0, "50"),
        (59.94, "59.94"), (60.0, "60")
    ]
    for (knownFPS, label) in known {
        if abs(fps - knownFPS) < 0.01 { return "\(label) fps" }
    }
    return String(format: "%.3f fps", fps)
}
