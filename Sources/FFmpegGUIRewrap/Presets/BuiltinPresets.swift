import Foundation

enum BuiltinPresets {
    static let all: [Preset] = [
        bt709Broadcast,
        hdr10,
        hlg,
        stripMetadata,
        afdRemove,
        mxfOP1a,
    ]

    static let bt709Broadcast: Preset = {
        var s = JobSettings()
        s.colorPrimaries = .bt709
        s.colorTransfer  = .bt709
        s.colorMatrix    = .bt709
        s.colorRange     = .limited
        s.fieldOrder     = .progressive
        return Preset(
            name: "BT.709 Broadcast",
            description: "HD broadcast color — BT.709 primaries, transfer, and matrix; limited range",
            settings: s,
            isBuiltIn: true
        )
    }()

    static let hdr10: Preset = {
        var s = JobSettings()
        s.colorPrimaries = .bt2020
        s.colorTransfer  = .smpte2084
        s.colorMatrix    = .bt2020nc
        s.colorRange     = .limited
        s.hdrMode        = .set
        s.masteringDisplay = .p3d65
        s.masteringDisplay.maxLuminance = 1000
        s.masteringDisplay.minLuminance = 0.005
        s.contentLightLevel = ContentLightLevel(maxCLL: 1000, maxFALL: 400)
        return Preset(
            name: "HDR10 (PQ, P3-D65 display)",
            description: "BT.2020/PQ with P3-D65 1000-nit mastering display metadata",
            settings: s,
            isBuiltIn: true
        )
    }()

    static let hlg: Preset = {
        var s = JobSettings()
        s.colorPrimaries = .bt2020
        s.colorTransfer  = .arib_std_b67
        s.colorMatrix    = .bt2020nc
        s.colorRange     = .limited
        return Preset(
            name: "HLG (Hybrid Log-Gamma)",
            description: "BT.2020 with HLG transfer — broadcast-compatible HDR",
            settings: s,
            isBuiltIn: true
        )
    }()

    static let stripMetadata: Preset = {
        var s = JobSettings()
        s.stripAllMetadata = true
        return Preset(
            name: "Strip All Metadata",
            description: "Remove all container and stream metadata tags",
            settings: s,
            isBuiltIn: true
        )
    }()

    static let afdRemove: Preset = {
        var s = JobSettings()
        s.afdMode = .remove
        return Preset(
            name: "Remove AFD",
            description: "Strip AFD SEI from the bitstream using a bitstream filter (no re-encode)",
            settings: s,
            isBuiltIn: true
        )
    }()

    static let mxfOP1a: Preset = {
        var s = JobSettings()
        s.outputFormat = .mxf
        s.mxfSettings.operationalPattern = .op1a
        s.mxfSettings.audioLayout = .paired
        s.mxfSettings.preserveUMID = true
        return Preset(
            name: "MXF OP1a Rewrap",
            description: "Rewrap to MXF OP1a with paired stereo audio, preserving UMID",
            settings: s,
            isBuiltIn: true
        )
    }()
}
