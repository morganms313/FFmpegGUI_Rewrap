import Foundation

// MARK: - FFprobe JSON structures

struct ProbeData: Codable {
    let streams: [StreamInfo]
    let format: FormatInfo
}

struct StreamInfo: Codable, Identifiable {
    let index: Int
    let codecName: String?
    let codecLongName: String?
    let codecType: String?   // "video", "audio", "data", "subtitle"
    let codecTagString: String?
    let profile: String?

    // Video
    let width: Int?
    let height: Int?
    let codedWidth: Int?
    let codedHeight: Int?
    let sampleAspectRatio: String?
    let displayAspectRatio: String?
    let pixFmt: String?
    let level: Int?
    let colorRange: String?
    let colorSpace: String?
    let colorTransfer: String?
    let colorPrimaries: String?
    let chromaLocation: String?
    let fieldOrder: String?
    let rFrameRate: String?
    let avgFrameRate: String?
    let bitsPerRawSample: String?
    let nbFrames: String?
    let sideDataList: [SideDataItem]?

    // Audio
    let sampleFmt: String?
    let sampleRate: String?
    let channels: Int?
    let channelLayout: String?
    let bitsPerSample: Int?

    // Common
    let bitRate: String?
    let duration: String?
    let timeBase: String?
    let startTime: String?
    let disposition: StreamDisposition?
    let tags: [String: String]?

    var id: Int { index }

    var codecTypeEnum: CodecType {
        switch codecType {
        case "video":    return .video
        case "audio":    return .audio
        case "data":     return .data
        case "subtitle": return .subtitle
        default:         return .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case index
        case codecName          = "codec_name"
        case codecLongName      = "codec_long_name"
        case codecType          = "codec_type"
        case codecTagString     = "codec_tag_string"
        case profile
        case width, height
        case codedWidth         = "coded_width"
        case codedHeight        = "coded_height"
        case sampleAspectRatio  = "sample_aspect_ratio"
        case displayAspectRatio = "display_aspect_ratio"
        case pixFmt             = "pix_fmt"
        case level
        case colorRange         = "color_range"
        case colorSpace         = "color_space"
        case colorTransfer      = "color_transfer"
        case colorPrimaries     = "color_primaries"
        case chromaLocation     = "chroma_location"
        case fieldOrder         = "field_order"
        case rFrameRate         = "r_frame_rate"
        case avgFrameRate       = "avg_frame_rate"
        case bitsPerRawSample   = "bits_per_raw_sample"
        case nbFrames           = "nb_frames"
        case sideDataList       = "side_data_list"
        case sampleFmt          = "sample_fmt"
        case sampleRate         = "sample_rate"
        case channels
        case channelLayout      = "channel_layout"
        case bitsPerSample      = "bits_per_sample"
        case bitRate            = "bit_rate"
        case duration
        case timeBase           = "time_base"
        case startTime          = "start_time"
        case disposition
        case tags
    }
}

struct SideDataItem: Codable {
    let sideDataType: String?
    // HDR mastering display
    let redX: String?;   let redY: String?
    let greenX: String?; let greenY: String?
    let blueX: String?;  let blueY: String?
    let whitePointX: String?; let whitePointY: String?
    let minLuminance: String?; let maxLuminance: String?
    // CLL
    let maxContent: Int?
    let maxAverage: Int?

    enum CodingKeys: String, CodingKey {
        case sideDataType   = "side_data_type"
        case redX           = "red_x";  case redY = "red_y"
        case greenX         = "green_x"; case greenY = "green_y"
        case blueX          = "blue_x"; case blueY = "blue_y"
        case whitePointX    = "white_point_x"; case whitePointY = "white_point_y"
        case minLuminance   = "min_luminance"; case maxLuminance = "max_luminance"
        case maxContent     = "max_content"; case maxAverage = "max_average"
    }
}

struct StreamDisposition: Codable {
    let `default`: Int?
    let forced: Int?
    let hearingImpaired: Int?
    let visualImpaired: Int?
    let original: Int?
    let comment: Int?

    enum CodingKeys: String, CodingKey {
        case `default`
        case forced
        case hearingImpaired = "hearing_impaired"
        case visualImpaired  = "visual_impaired"
        case original
        case comment
    }
}

struct FormatInfo: Codable {
    let filename: String
    let formatName: String?
    let formatLongName: String?
    let duration: String?
    let size: String?
    let bitRate: String?
    let probeScore: Int?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case filename
        case formatName     = "format_name"
        case formatLongName = "format_long_name"
        case duration
        case size
        case bitRate        = "bit_rate"
        case probeScore     = "probe_score"
        case tags
    }

    var durationSeconds: Double? {
        guard let d = duration else { return nil }
        return Double(d)
    }
    var sizeBytes: Int64? {
        guard let s = size else { return nil }
        return Int64(s)
    }
    var sizeMB: String? {
        guard let b = sizeBytes else { return nil }
        return String(format: "%.1f MB", Double(b) / 1_000_000)
    }
    var durationFormatted: String? {
        guard let s = durationSeconds else { return nil }
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        let sec = Int(s) % 60
        let frames = Int((s.truncatingRemainder(dividingBy: 1)) * 100)
        return h > 0
            ? String(format: "%d:%02d:%02d.%02d", h, m, sec, frames)
            : String(format: "%02d:%02d.%02d", m, sec, frames)
    }
}

enum CodecType {
    case video, audio, data, subtitle, unknown
}

// MARK: - MediaFile

@Observable
class MediaFile: Identifiable {
    let id: UUID = UUID()
    let url: URL
    var probeData: ProbeData?
    var probeError: String?
    var isProbing: Bool = false

    init(url: URL) {
        self.url = url
    }

    var filename: String { url.lastPathComponent }
    var displayName: String { url.deletingPathExtension().lastPathComponent }

    var videoStreams: [StreamInfo] {
        probeData?.streams.filter { $0.codecTypeEnum == .video } ?? []
    }
    var audioStreams: [StreamInfo] {
        probeData?.streams.filter { $0.codecTypeEnum == .audio } ?? []
    }
    var dataStreams: [StreamInfo] {
        probeData?.streams.filter { $0.codecTypeEnum == .data } ?? []
    }

    var primaryVideo: StreamInfo? { videoStreams.first }

    var formatName: String {
        probeData?.format.formatName ?? url.pathExtension.uppercased()
    }

    /// Build initial AudioTrackSettings from probed streams
    func defaultAudioTrackSettings() -> [AudioTrackSettings] {
        audioStreams.map { stream in
            AudioTrackSettings(
                id: stream.index,
                language: stream.tags?["language"],
                title: stream.tags?["title"] ?? stream.tags?["handler_name"],
                channelLayout: nil,
                dialnorm: nil,
                isDefault: stream.disposition?.default == 1,
                isForced: stream.disposition?.forced == 1,
                isHearingImpaired: stream.disposition?.hearingImpaired == 1
            )
        }
    }
}
