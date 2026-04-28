import Foundation

// MARK: - Container / Output

enum OutputFormat: String, CaseIterable, Codable, Identifiable {
    case mov, mxf, mp4, mkv, ts
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mov: return "QuickTime (.mov)"
        case .mxf: return "MXF (.mxf)"
        case .mp4: return "MPEG-4 (.mp4)"
        case .mkv: return "Matroska (.mkv)"
        case .ts:  return "MPEG-TS (.ts)"
        }
    }
    var fileExtension: String { rawValue }
    var ffmpegMuxer: String {
        switch self {
        case .mov: return "mov"
        case .mxf: return "mxf"
        case .mp4: return "mp4"
        case .mkv: return "matroska"
        case .ts:  return "mpegts"
        }
    }
}

// MARK: - Color

enum ColorPrimaries: String, CaseIterable, Codable, Identifiable {
    case bt709      = "bt709"
    case bt470m     = "bt470m"
    case bt470bg    = "bt470bg"
    case smpte170m  = "smpte170m"
    case smpte240m  = "smpte240m"
    case film       = "film"
    case bt2020     = "bt2020"
    case smpte428   = "smpte428"
    case smpte431   = "smpte431"
    case smpte432   = "smpte432"   // P3-D65
    case jedec_p22  = "jedec-p22"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .bt709:     return "BT.709 (HD)"
        case .bt470m:    return "BT.470M (NTSC film)"
        case .bt470bg:   return "BT.470BG (PAL/SECAM)"
        case .smpte170m: return "SMPTE 170M (NTSC)"
        case .smpte240m: return "SMPTE 240M"
        case .film:      return "Film (C)"
        case .bt2020:    return "BT.2020 (UHD)"
        case .smpte428:  return "SMPTE 428 / DCI-XYZ"
        case .smpte431:  return "SMPTE 431 / DCI-P3"
        case .smpte432:  return "SMPTE 432 / P3-D65"
        case .jedec_p22: return "JEDEC P22"
        }
    }
}

enum ColorTransfer: String, CaseIterable, Codable, Identifiable {
    case bt709          = "bt709"
    case gamma22        = "gamma22"
    case gamma28        = "gamma28"
    case smpte170m      = "smpte170m"
    case smpte240m      = "smpte240m"
    case linear         = "linear"
    case log            = "log"
    case log316         = "log316"
    case iec61966_2_4   = "iec61966-2-4"
    case bt1361e        = "bt1361e"
    case iec61966_2_1   = "iec61966-2-1"  // sRGB
    case bt2020_10      = "bt2020-10"
    case bt2020_12      = "bt2020-12"
    case smpte2084      = "smpte2084"      // PQ / HDR10
    case smpte428       = "smpte428"
    case arib_std_b67   = "arib-std-b67"  // HLG
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .bt709:        return "BT.709"
        case .gamma22:      return "Gamma 2.2"
        case .gamma28:      return "Gamma 2.8"
        case .smpte170m:    return "SMPTE 170M"
        case .smpte240m:    return "SMPTE 240M"
        case .linear:       return "Linear"
        case .log:          return "Log (100:1)"
        case .log316:       return "Log (316:1)"
        case .iec61966_2_4: return "IEC 61966-2-4 (xvYCC)"
        case .bt1361e:      return "BT.1361E"
        case .iec61966_2_1: return "IEC 61966-2-1 (sRGB)"
        case .bt2020_10:    return "BT.2020 10-bit"
        case .bt2020_12:    return "BT.2020 12-bit"
        case .smpte2084:    return "SMPTE ST 2084 (PQ/HDR10)"
        case .smpte428:     return "SMPTE 428 (DCI)"
        case .arib_std_b67: return "ARIB STD-B67 (HLG)"
        }
    }
}

enum ColorMatrix: String, CaseIterable, Codable, Identifiable {
    case rgb                = "rgb"
    case bt709              = "bt709"
    case fcc                = "fcc"
    case bt470bg            = "bt470bg"
    case smpte170m          = "smpte170m"
    case smpte240m          = "smpte240m"
    case ycgco              = "ycgco"
    case bt2020nc           = "bt2020nc"
    case bt2020c            = "bt2020c"
    case smpte2085          = "smpte2085"
    case chroma_derived_nc  = "chroma-derived-nc"
    case chroma_derived_c   = "chroma-derived-c"
    case ictcp              = "ictcp"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .rgb:               return "Identity / RGB"
        case .bt709:             return "BT.709"
        case .fcc:               return "FCC"
        case .bt470bg:           return "BT.470BG (PAL)"
        case .smpte170m:         return "SMPTE 170M (NTSC)"
        case .smpte240m:         return "SMPTE 240M"
        case .ycgco:             return "YCgCo"
        case .bt2020nc:          return "BT.2020 NCL"
        case .bt2020c:           return "BT.2020 CL"
        case .smpte2085:         return "SMPTE 2085"
        case .chroma_derived_nc: return "Chroma-derived NCL"
        case .chroma_derived_c:  return "Chroma-derived CL"
        case .ictcp:             return "ICtCp"
        }
    }
}

enum ColorRange: String, CaseIterable, Codable, Identifiable {
    case limited = "tv"
    case full    = "pc"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .limited: return "Limited / Broadcast (16–235)"
        case .full:    return "Full / PC (0–255)"
        }
    }
}

enum ChromaSampleLocation: String, CaseIterable, Codable, Identifiable {
    case left        = "left"
    case center      = "center"
    case topleft     = "topleft"
    case top         = "top"
    case bottomleft  = "bottomleft"
    case bottom      = "bottom"
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum FieldOrder: String, CaseIterable, Codable, Identifiable {
    case progressive = "progressive"
    case topFirst    = "tt"
    case bottomFirst = "bb"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .progressive: return "Progressive"
        case .topFirst:    return "Interlaced — Top Field First"
        case .bottomFirst: return "Interlaced — Bottom Field First"
        }
    }
}

// MARK: - AFD

enum AFDMode: String, CaseIterable, Codable, Identifiable {
    case preserve = "Preserve"
    case remove   = "Remove"
    case set      = "Set"
    var id: String { rawValue }
}

struct BarData: Codable, Equatable {
    var topBar: Int    = 0
    var bottomBar: Int = 0
    var leftBar: Int   = 0
    var rightBar: Int  = 0
}

// MARK: - HDR

enum HDRMode: String, CaseIterable, Codable, Identifiable {
    case preserve = "Preserve"
    case strip    = "Strip"
    case set      = "Set"
    var id: String { rawValue }
}

struct MasteringDisplayMetadata: Codable, Equatable {
    // Chromaticity coordinates
    var redX:   Double = 0.680; var redY:   Double = 0.320
    var greenX: Double = 0.265; var greenY: Double = 0.690
    var blueX:  Double = 0.150; var blueY:  Double = 0.060
    var whiteX: Double = 0.3127; var whiteY: Double = 0.3290
    // Luminance (cd/m²)
    var minLuminance: Double = 0.005
    var maxLuminance: Double = 1000.0

    // Common display primaries presets
    static let bt2020: MasteringDisplayMetadata = {
        var m = MasteringDisplayMetadata()
        m.redX = 0.708; m.redY = 0.292
        m.greenX = 0.170; m.greenY = 0.797
        m.blueX = 0.131; m.blueY = 0.046
        return m
    }()
    static let p3d65: MasteringDisplayMetadata = {
        var m = MasteringDisplayMetadata()
        m.redX = 0.680; m.redY = 0.320
        m.greenX = 0.265; m.greenY = 0.690
        m.blueX = 0.150; m.blueY = 0.060
        return m
    }()
    static let dciP3: MasteringDisplayMetadata = {
        var m = MasteringDisplayMetadata()
        m.redX = 0.680; m.redY = 0.320
        m.greenX = 0.265; m.greenY = 0.690
        m.blueX = 0.150; m.blueY = 0.060
        m.whiteX = 0.314; m.whiteY = 0.351
        return m
    }()
}

struct ContentLightLevel: Codable, Equatable {
    var maxCLL:  Int = 1000
    var maxFALL: Int = 400
}

// MARK: - Timecode

enum TimecodeMode: String, CaseIterable, Codable, Identifiable {
    case preserve = "Preserve"
    case remove   = "Remove"
    case set      = "Set"
    var id: String { rawValue }
}

// MARK: - Audio

enum ChannelLayout: String, CaseIterable, Codable, Identifiable {
    case mono          = "mono"
    case stereo        = "stereo"
    case twoOne        = "2.1"
    case threeZero     = "3.0"
    case fourZero      = "4.0"
    case fiveZero      = "5.0"
    case fiveOne       = "5.1"
    case fiveOneSide   = "5.1(side)"
    case sixOne        = "6.1"
    case sevenOne      = "7.1"
    case sevenOneWide  = "7.1(wide)"
    case ltRt          = "ltrt"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .mono:         return "Mono"
        case .stereo:       return "Stereo"
        case .twoOne:       return "2.1"
        case .threeZero:    return "3.0"
        case .fourZero:     return "4.0"
        case .fiveZero:     return "5.0"
        case .fiveOne:      return "5.1"
        case .fiveOneSide:  return "5.1 (side)"
        case .sixOne:       return "6.1"
        case .sevenOne:     return "7.1"
        case .sevenOneWide: return "7.1 Wide"
        case .ltRt:         return "Lt/Rt (Matrixed Stereo)"
        }
    }
    /// The FFmpeg channel layout string (ltrt maps to stereo layout)
    var ffmpegLayout: String {
        self == .ltRt ? "stereo" : rawValue
    }
}

struct AudioTrackSettings: Codable, Identifiable, Equatable {
    var id: Int                             // stream index
    var language: String?                   // ISO 639-2
    var title: String?
    var channelLayout: ChannelLayout?
    var dialnorm: Int?                      // -31 to 0 dB
    var isDefault: Bool?
    var isForced: Bool?
    var isHearingImpaired: Bool?
}

// MARK: - MXF

enum MXFOperationalPattern: String, CaseIterable, Codable, Identifiable {
    case op1a    = "op1a"
    case opAtom  = "op-atom"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .op1a:   return "OP1a — Interleaved"
        case .opAtom: return "OP-Atom — Single-essence"
        }
    }
}

enum MXFAudioLayout: String, CaseIterable, Codable, Identifiable {
    case mono        = "Mono tracks"
    case paired      = "Paired stereo"
    case multiChannel = "Multi-channel"
    var id: String { rawValue }
}

struct MXFSettings: Codable, Equatable {
    var operationalPattern: MXFOperationalPattern = .op1a
    var audioLayout: MXFAudioLayout               = .paired
    var preserveUMID: Bool                        = true
    var regenerateSourcePackageUID: Bool          = false
    var preserveKLV: Bool                         = true
}

// MARK: - QuickTime

enum ProResProfile: String, CaseIterable, Codable, Identifiable {
    case proxy    = "proxy"
    case lt       = "lt"
    case standard = "standard"
    case hq       = "hq"
    case p4444    = "4444"
    case p4444xq  = "4444xq"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .proxy:    return "ProRes 422 Proxy"
        case .lt:       return "ProRes 422 LT"
        case .standard: return "ProRes 422"
        case .hq:       return "ProRes 422 HQ"
        case .p4444:    return "ProRes 4444"
        case .p4444xq:  return "ProRes 4444 XQ"
        }
    }
}

struct QuickTimeSettings: Codable, Equatable {
    var reelName: String?
    var clipName: String?
    var overrideProResProfile: Bool     = false
    var proResProfile: ProResProfile    = .standard
    var preserveCameraMetadata: Bool    = true
    var manageTmcdTrack: TmcdTrackMode  = .preserve
    var spatialVideoMode: SpatialVideoMode = .preserve
}

enum TmcdTrackMode: String, CaseIterable, Codable, Identifiable {
    case preserve = "Preserve"
    case remove   = "Remove"
    case add      = "Add"
    var id: String { rawValue }
}

enum SpatialVideoMode: String, CaseIterable, Codable, Identifiable {
    case preserve    = "Preserve"
    case strip       = "Strip"
    case markStereo  = "Mark as Stereoscopic"
    var id: String { rawValue }
}

// MARK: - General Metadata

struct GeneralMetadata: Codable, Equatable {
    var title: String?
    var comment: String?
    var description: String?
    var copyright: String?
    var encoder: String?
    var artist: String?
    var album: String?
    var date: String?
    var genre: String?
    var customPairs: [String: String] = [:]
}

// MARK: - Output Filename

enum FilenameTemplate: String, CaseIterable, Codable, Identifiable {
    case nameRewrap    = "{name}_rewrap"
    case nameDate      = "{name}_{date}"
    case nameSuffix    = "{name}_out"
    case custom        = "Custom…"
    var id: String { rawValue }
    var displayName: String { rawValue }
}

// MARK: - JobSettings (root model)

struct JobSettings: Codable, Equatable {

    // MARK: Container
    var outputFormat: OutputFormat = .mov

    // MARK: Color (nil = preserve / don't touch)
    var colorPrimaries: ColorPrimaries?
    var colorTransfer: ColorTransfer?
    var colorMatrix: ColorMatrix?
    var colorRange: ColorRange?
    var chromaSampleLocation: ChromaSampleLocation?
    var fieldOrder: FieldOrder?

    // MARK: Geometry
    var sarOverride: String?       // e.g. "1:1"
    var darOverride: String?       // e.g. "16:9"
    var frameRateOverride: String? // e.g. "24000/1001"

    // MARK: AFD
    var afdMode: AFDMode = .preserve
    var afdCode: Int     = 8       // default: AFD_8 (full frame 16:9)
    var includeBarData: Bool = false
    var barData: BarData = BarData()

    // MARK: HDR
    var hdrMode: HDRMode = .preserve
    var masteringDisplay: MasteringDisplayMetadata = MasteringDisplayMetadata()
    var contentLightLevel: ContentLightLevel       = ContentLightLevel()
    var stripDolbyVisionRPU: Bool = false
    var stripHDR10Plus: Bool      = false

    // MARK: Timecode
    var timecodeMode: TimecodeMode = .preserve
    var timecodeStart: String      = "01:00:00:00"
    var timecodeDropFrame: Bool    = false

    // MARK: Audio (per-track)
    var audioTracks: [AudioTrackSettings] = []

    // MARK: MXF
    var mxfSettings: MXFSettings = MXFSettings()

    // MARK: QuickTime
    var quickTimeSettings: QuickTimeSettings = QuickTimeSettings()

    // MARK: General metadata
    var generalMetadata: GeneralMetadata = GeneralMetadata()
    var stripAllMetadata: Bool = false

    // MARK: Output
    var outputDirectory: String?
    var filenameTemplate: FilenameTemplate = .nameRewrap
    var customFilenameTemplate: String     = "{name}_rewrap"
}
