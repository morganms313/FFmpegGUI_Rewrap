import Foundation

struct BuildResult {
    let args: [String]
    let requiresRender: Bool
    let renderReasons: [String]
    /// Human-readable command string for display
    var displayCommand: String {
        (["ffmpeg"] + args).map { arg in
            arg.contains(" ") ? "\"\(arg)\"" : arg
        }.joined(separator: " \\\n  ")
    }
}

class CommandBuilder {

    func build(mediaFile: MediaFile, settings: JobSettings, outputURL: URL) -> BuildResult {
        var args: [String] = []
        var bsfVideoFilters: [String] = []
        var requiresRender = false
        var renderReasons: [String] = []

        let videoCodec  = mediaFile.primaryVideo?.codecName ?? ""
        let isH264      = videoCodec == "h264"
        let isHEVC      = videoCodec.hasPrefix("hevc") || videoCodec == "h265"
        let supportsColorBSF = isH264 || isHEVC

        // MARK: Input
        args += ["-i", mediaFile.url.path]

        // MARK: Stream copy (default)
        args += ["-c", "copy"]

        // MARK: Output format
        args += ["-f", settings.outputFormat.ffmpegMuxer]

        // MARK: Strip all metadata
        if settings.stripAllMetadata {
            args += ["-map_metadata", "-1"]
        }

        // MARK: Color metadata
        // Container-level tags (stream copy compatible)
        if let primaries = settings.colorPrimaries {
            args += ["-color_primaries:v", primaries.rawValue]
        }
        if let transfer = settings.colorTransfer {
            args += ["-color_trc:v", transfer.rawValue]
        }
        if let matrix = settings.colorMatrix {
            args += ["-colorspace:v", matrix.rawValue]
        }
        if let range = settings.colorRange {
            args += ["-color_range:v", range.rawValue]
        }

        // Bitstream-level color (VUI) for H.264 / HEVC — no re-encode needed
        if supportsColorBSF, settings.colorPrimaries != nil || settings.colorTransfer != nil || settings.colorMatrix != nil || settings.colorRange != nil {
            var bsfParts: [String] = []
            if let p = settings.colorPrimaries  { bsfParts.append("colour_primaries=\(primariesBSFValue(p))") }
            if let t = settings.colorTransfer   { bsfParts.append("transfer_characteristics=\(transferBSFValue(t))") }
            if let m = settings.colorMatrix     { bsfParts.append("matrix_coefficients=\(matrixBSFValue(m))") }
            if let r = settings.colorRange      { bsfParts.append("video_full_range_flag=\(r == .full ? 1 : 0)") }
            if !bsfParts.isEmpty {
                let bsfName = isH264 ? "h264_metadata" : "hevc_metadata"
                bsfVideoFilters.append("\(bsfName)=\(bsfParts.joined(separator: ":"))")
            }
        }

        // Chroma location (container tag only)
        if let chroma = settings.chromaSampleLocation {
            args += ["-chroma_sample_location:v", chroma.rawValue]
        }

        // MARK: Field order
        if let fieldOrder = settings.fieldOrder {
            args += ["-field_order:v", fieldOrder.rawValue]
        }

        // MARK: Geometry overrides
        if let sar = settings.sarOverride, !sar.isEmpty {
            args += ["-sar:v", sar]
        }
        if let dar = settings.darOverride, !dar.isEmpty {
            // DAR is expressed as a rational in the container; use setdar filter if stream copy won't accept it
            args += ["-aspect:v", dar]
        }
        if let fps = settings.frameRateOverride, !fps.isEmpty {
            // Override the container-reported frame rate without re-encoding.
            // Accepts rational notation (e.g. 24000/1001) or decimal (e.g. 23.976).
            args += ["-r:v", fps]
        }

        // MARK: AFD
        switch settings.afdMode {
        case .preserve:
            break
        case .remove:
            // Strip AFD SEI (type 6) from the bitstream using filter_units BSF
            if isH264 || isHEVC {
                // SEI payload type 6 = active_format_description
                bsfVideoFilters.append("filter_units=remove_types=6")
            }
        case .set:
            // setparams filter can inject AFD but requires a video filter chain → render
            requiresRender = true
            renderReasons.append("AFD injection via setparams requires video filter (re-encode)")
            // Will be handled by the render path; flag here for UI
        }

        // MARK: HDR
        switch settings.hdrMode {
        case .preserve:
            break
        case .strip:
            // Remove MDCV/CLL SEI units
            if isH264 || isHEVC {
                bsfVideoFilters.append("filter_units=remove_types=137:144:145")
            }
        case .set:
            let md = settings.masteringDisplay
            // Chromaticity values as fractions with 50000 denominator (SMPTE 2086 encoding)
            let mdStr = String(format:
                "G(%d/%d,%d/%d)B(%d/%d,%d/%d)R(%d/%d,%d/%d)WP(%d/%d,%d/%d)L(%d/%d,%d/%d)",
                Int(md.greenX * 50000), 50000, Int(md.greenY * 50000), 50000,
                Int(md.blueX  * 50000), 50000, Int(md.blueY  * 50000), 50000,
                Int(md.redX   * 50000), 50000, Int(md.redY   * 50000), 50000,
                Int(md.whiteX * 50000), 50000, Int(md.whiteY * 50000), 50000,
                Int(md.maxLuminance * 10000), 10000, Int(md.minLuminance * 10000), 10000
            )
            args += ["-metadata:s:v:0", "master_display=\(mdStr)"]

            let cll = settings.contentLightLevel
            args += ["-metadata:s:v:0", "max_cll=\(cll.maxCLL),\(cll.maxFALL)"]
        }

        if settings.stripDolbyVisionRPU, isHEVC {
            bsfVideoFilters.append("filter_units=remove_types=62")  // Dolby Vision RPU
        }
        if settings.stripHDR10Plus, isHEVC {
            bsfVideoFilters.append("filter_units=remove_types=0x01C8")  // HDR10+ SEI
        }

        // MARK: Apply BSF filters
        if !bsfVideoFilters.isEmpty {
            args += ["-bsf:v", bsfVideoFilters.joined(separator: ",")]
        }

        // MARK: Timecode
        switch settings.timecodeMode {
        case .preserve:
            break
        case .remove:
            // Map all streams then exclude data streams (which include the tmcd track in MOV/MXF).
            // The negative specifier requires a prior positive map to work correctly.
            args += ["-map", "0", "-map", "-0:d"]
        case .set:
            // timecodeStart is already formatted with ':' (non-drop) or ';' (drop-frame) as the
            // last separator by the view — FFmpeg reads this separator to set the drop-frame flag.
            args += ["-timecode", settings.timecodeStart]
        }

        // MARK: General metadata
        if !settings.stripAllMetadata {
            let gm = settings.generalMetadata
            appendMetadata(&args, key: "title",       value: gm.title)
            appendMetadata(&args, key: "comment",     value: gm.comment)
            appendMetadata(&args, key: "description", value: gm.description)
            appendMetadata(&args, key: "copyright",   value: gm.copyright)
            appendMetadata(&args, key: "encoder",     value: gm.encoder)
            appendMetadata(&args, key: "artist",      value: gm.artist)
            appendMetadata(&args, key: "album",       value: gm.album)
            appendMetadata(&args, key: "date",        value: gm.date)
            appendMetadata(&args, key: "genre",       value: gm.genre)
            for (k, v) in gm.customPairs {
                args += ["-metadata", "\(k)=\(v)"]
            }
        }

        // MARK: Audio track metadata
        // audioIndex is 0-based within audio streams; track.id is the global stream index.
        // • -metadata uses the "s:a:N" form (s = stream-type prefix for metadata specifiers)
        // • -disposition / -channel_layout use plain stream specifiers: "a:N"
        for (audioIndex, track) in settings.audioTracks.enumerated() {
            let metaSpec   = "s:a:\(audioIndex)"   // for -metadata:…
            let streamSpec =   "a:\(audioIndex)"   // for -disposition:… / -channel_layout:…
            appendMetadata(&args, key: "language", value: track.language, specifier: metaSpec)
            appendMetadata(&args, key: "title",    value: track.title,    specifier: metaSpec)
            if let layout = track.channelLayout {
                args += ["-channel_layout:\(streamSpec)", layout.ffmpegLayout]
            }
            // Disposition flags
            var dispParts: [String] = []
            if let def    = track.isDefault        { dispParts.append(def    ? "+default"           : "-default") }
            if let forced = track.isForced         { dispParts.append(forced ? "+forced"             : "-forced") }
            if let hi     = track.isHearingImpaired{ dispParts.append(hi     ? "+hearing_impaired"   : "-hearing_impaired") }
            if !dispParts.isEmpty {
                args += ["-disposition:\(streamSpec)", dispParts.joined()]
            }
        }

        // MARK: MXF-specific
        if settings.outputFormat == .mxf {
            // OP pattern
            args += ["-operational_pattern", settings.mxfSettings.operationalPattern.rawValue]
            if !settings.mxfSettings.preserveUMID {
                args += ["-write_umid", "0"]
            }
        }

        // MARK: QuickTime-specific
        if settings.outputFormat == .mov {
            let qt = settings.quickTimeSettings
            if let reel = qt.reelName, !reel.isEmpty {
                args += ["-metadata", "reel_name=\(reel)"]
            }
            if let clip = qt.clipName, !clip.isEmpty {
                args += ["-metadata", "com.apple.proapps.clipname=\(clip)"]
            }
            // tmcd track
            switch qt.manageTmcdTrack {
            case .preserve: break
            case .remove:
                // Negative map specifiers require a prior positive map; -0:d drops all data streams.
                // Only add the pair if timecode removal hasn't already inserted them.
                if settings.timecodeMode != .remove {
                    args += ["-map", "0", "-map", "-0:d"]
                }
            case .add: break  // handled via timecode .set path
            }
        }

        // MARK: Output path
        args += [outputURL.path]

        return BuildResult(args: args, requiresRender: requiresRender, renderReasons: renderReasons)
    }

    // MARK: - Helpers

    private func appendMetadata(_ args: inout [String], key: String, value: String?, specifier: String? = nil) {
        guard let v = value, !v.isEmpty else { return }
        let flag = specifier != nil ? "-metadata:\(specifier!)" : "-metadata"
        args += [flag, "\(key)=\(v)"]
    }

    // MARK: BSF integer value mappings

    private func primariesBSFValue(_ p: ColorPrimaries) -> Int {
        switch p {
        case .bt709:     return 1
        case .bt470m:    return 4
        case .bt470bg:   return 5
        case .smpte170m: return 6
        case .smpte240m: return 7
        case .film:      return 8
        case .bt2020:    return 9
        case .smpte428:  return 10
        case .smpte431:  return 11
        case .smpte432:  return 12
        case .jedec_p22: return 22
        }
    }

    private func transferBSFValue(_ t: ColorTransfer) -> Int {
        switch t {
        case .bt709:        return 1
        case .gamma22:      return 4
        case .gamma28:      return 5
        case .smpte170m:    return 6
        case .smpte240m:    return 7
        case .linear:       return 8
        case .log:          return 9
        case .log316:       return 10
        case .iec61966_2_4: return 11
        case .bt1361e:      return 12
        case .iec61966_2_1: return 13
        case .bt2020_10:    return 14
        case .bt2020_12:    return 15
        case .smpte2084:    return 16
        case .smpte428:     return 17
        case .arib_std_b67: return 18
        }
    }

    private func matrixBSFValue(_ m: ColorMatrix) -> Int {
        switch m {
        case .rgb:               return 0
        case .bt709:             return 1
        case .fcc:               return 4
        case .bt470bg:           return 5
        case .smpte170m:         return 6
        case .smpte240m:         return 7
        case .ycgco:             return 8
        case .bt2020nc:          return 9
        case .bt2020c:           return 10
        case .smpte2085:         return 11
        case .chroma_derived_nc: return 12
        case .chroma_derived_c:  return 13
        case .ictcp:             return 14
        }
    }
}
