import Foundation

/// Patches QuickTime container atoms (stts / mdhd / tkhd / mvhd / elst) to conform the
/// declared frame rate without re-encoding the video or audio bitstream.
///
/// This is equivalent to what tools like cineXmeta do: direct in-place atom surgery on the
/// QuickTime atom tree, touching only the timing fields that players / MediaInfo read.
struct QTConformer {

    // MARK: - Public API

    /// Conform `url` in-place to `targetFPS`, optionally restoring the original mvhd timescale.
    ///
    /// - Parameters:
    ///   - url: Path to a `.mov` or `.mp4` file (must be writable).
    ///   - targetFPS: Rational string — `"24"`, `"24000/1001"`, or decimal like `"23.976"`.
    ///   - originalMovieTimescale: If provided and different from what the file currently
    ///     contains, the mvhd timescale field is restored to this value and all movie-timescale-
    ///     denominated durations (mvhd, tkhd, elst) are recomputed accordingly. This corrects
    ///     FFmpeg's MOV muxer silently normalising the timescale to 1000.
    static func conform(url: URL, targetFPS: String, originalMovieTimescale: Int64? = nil) throws {
        // 1. Locate moov and read ONLY that atom (typically a few MB; mdat can be GB).
        //    This is essential for files on network volumes where mapping the entire
        //    file would either fail or copy multi-GB into RAM.
        let (moovData, moovOffset) = try readMoovOnly(url: url)

        // 2. Parse the FPS into a rational.
        let fps = try parseFPS(targetFPS)

        // 3. Walk moov and collect patches (offsets are within moovData).
        let ctx = ConformContext(data: moovData, fps: fps, originalMovieTimescale: originalMovieTimescale)
        try ctx.findMoov()

        // 4. Apply all patches via FileHandle, translating offsets to absolute file
        //    positions by adding moovOffset.
        let fh = try FileHandle(forUpdating: url)
        defer { fh.synchronizeFile(); try? fh.close() }
        for patch in ctx.patches.sorted(by: { $0.offset < $1.offset }) {
            try fh.seek(toOffset: moovOffset + UInt64(patch.offset))
            fh.write(Data(patch.bytes))
        }
    }

    /// Read just the mvhd timescale from `url`. Reads only the moov atom, not the whole file.
    static func readMovieTimescale(url: URL) -> Int64? {
        guard let (moovData, _) = try? readMoovOnly(url: url) else { return nil }
        // moovData starts with the moov atom itself, so findMoov sees it at offset 0.
        return readMvhdTimescaleInMoov(data: moovData)
    }

    /// Scan top-level atoms via FileHandle (reading only 8-byte headers) until moov is found,
    /// then read just that atom's bytes. Avoids materialising mdat in memory.
    private static func readMoovOnly(url: URL) throws -> (moovData: Data, moovFileOffset: UInt64) {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let fileSize = try fh.seekToEnd()
        try fh.seek(toOffset: 0)

        var cursor: UInt64 = 0
        while cursor + 8 <= fileSize {
            try fh.seek(toOffset: cursor)
            let header = fh.readData(ofLength: 8)
            guard header.count == 8 else { break }
            let rawSize = UInt32(header[0]) << 24 | UInt32(header[1]) << 16
                        | UInt32(header[2]) << 8  | UInt32(header[3])
            let type = String(bytes: header[4..<8], encoding: .isoLatin1) ?? "????"

            var atomSize: UInt64
            if rawSize == 1 {
                let ext = fh.readData(ofLength: 8)
                guard ext.count == 8 else { break }
                atomSize = (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(ext[$1]) }
            } else if rawSize == 0 {
                atomSize = fileSize - cursor
            } else {
                atomSize = UInt64(rawSize)
            }
            guard atomSize >= 8 else { throw QTConformerError.malformedAtom }

            if type == "moov" {
                try fh.seek(toOffset: cursor)
                let moovBytes = fh.readData(ofLength: Int(atomSize))
                guard moovBytes.count == Int(atomSize) else { throw QTConformerError.malformedAtom }
                return (moovBytes, cursor)
            }
            cursor += atomSize
        }
        throw QTConformerError.noMoovAtom
    }

    /// Reads mvhd timescale from a Data buffer that begins with a moov atom.
    private static func readMvhdTimescaleInMoov(data: Data) -> Int64? {
        guard let (size, type, headerSz) = try? atomHeader(data: data, at: 0), type == "moov" else { return nil }
        var cursor = headerSz
        let end = size
        while cursor < end - 7 {
            guard let (childSize, childType, childHeader) = try? atomHeader(data: data, at: cursor) else { break }
            if childType == "mvhd" {
                let versionOff = cursor + childHeader
                guard versionOff < data.count else { break }
                let version = data[versionOff]
                let tsOff = versionOff + (version == 1 ? 20 : 12)
                return try? readUInt32(data: data, at: tsOff)
            }
            let next = cursor + childSize
            guard next > cursor else { break }
            cursor = next
        }
        return nil
    }

    // Static helpers used by the read-only path above.
    private static func atomHeader(data: Data, at offset: Int) throws -> (size: Int, type: String, headerSize: Int) {
        guard offset + 8 <= data.count else { throw QTConformerError.malformedAtom }
        let rawSize = Int(try readUInt32(data: data, at: offset))
        let type = String(bytes: data[offset+4..<offset+8], encoding: .isoLatin1) ?? "????"
        if rawSize == 1 {
            guard offset + 16 <= data.count else { throw QTConformerError.malformedAtom }
            let ext = Int(try readUInt64(data: data, at: offset + 8))
            return (ext, type, 16)
        }
        return (rawSize == 0 ? data.count - offset : rawSize, type, 8)
    }
    private static func readUInt32(data: Data, at offset: Int) throws -> Int64 {
        guard offset + 4 <= data.count else { throw QTConformerError.malformedAtom }
        return Int64(UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16
                   | UInt32(data[offset+2]) << 8  | UInt32(data[offset+3]))
    }
    private static func readUInt64(data: Data, at offset: Int) throws -> UInt64 {
        guard offset + 8 <= data.count else { throw QTConformerError.malformedAtom }
        let hi = UInt64(data[offset]) << 56 | UInt64(data[offset+1]) << 48
               | UInt64(data[offset+2]) << 40 | UInt64(data[offset+3]) << 32
        let lo = UInt64(data[offset+4]) << 24 | UInt64(data[offset+5]) << 16
               | UInt64(data[offset+6]) << 8  | UInt64(data[offset+7])
        return hi | lo
    }

    // MARK: - FPS parsing

    private struct Rational {
        let num: Int64
        let den: Int64
        var asDouble: Double { Double(num) / Double(den) }
    }

    /// Known broadcast rationals for decimal snap.
    private static let knownRationals: [(Double, Rational)] = [
        (23.976, Rational(num: 24000, den: 1001)),
        (24.0,   Rational(num: 24,    den: 1)),
        (25.0,   Rational(num: 25,    den: 1)),
        (29.97,  Rational(num: 30000, den: 1001)),
        (30.0,   Rational(num: 30,    den: 1)),
        (47.952, Rational(num: 48000, den: 1001)),
        (48.0,   Rational(num: 48,    den: 1)),
        (50.0,   Rational(num: 50,    den: 1)),
        (59.94,  Rational(num: 60000, den: 1001)),
        (60.0,   Rational(num: 60,    den: 1)),
        (120.0,  Rational(num: 120,   den: 1)),
    ]

    private static func parseFPS(_ s: String) throws -> Rational {
        let trimmed = s.trimmingCharacters(in: .whitespaces)

        // Rational form: "24000/1001"
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", maxSplits: 1)
            guard parts.count == 2,
                  let num = Int64(parts[0].trimmingCharacters(in: .whitespaces)),
                  let den = Int64(parts[1].trimmingCharacters(in: .whitespaces)),
                  den > 0, num > 0
            else { throw QTConformerError.invalidFPS(trimmed) }
            return Rational(num: num, den: den)
        }

        // Integer form: "24"
        if let i = Int64(trimmed), i > 0 {
            return Rational(num: i, den: 1)
        }

        // Decimal form: snap to nearest known rational within ±0.01
        if let d = Double(trimmed) {
            for (ref, rational) in knownRationals {
                if abs(d - ref) < 0.011 { return rational }
            }
            throw QTConformerError.invalidFPS(trimmed)
        }

        throw QTConformerError.invalidFPS(trimmed)
    }

    // MARK: - Atom walking context

    private class ConformContext {
        let data: Data
        let fps: Rational
        var patches: [Patch] = []

        // Collected from the video track's mdhd
        var mediaTimescale: Int64 = 0    // original mdhd timescale (read from file)
        var newMediaTimescale: Int64 = 0 // mdhd timescale to write — equals mediaTimescale
                                         // unless the rate doesn't divide cleanly
        var newDelta: Int64 = 0          // stts delta value, in newMediaTimescale units
        var totalSamples: Int64 = 0
        var newMediaDuration: Int64 = 0  // totalSamples * newDelta (in newMediaTimescale units)
        var movieTimescale: Int64 = 0    // read from output file's mvhd

        /// Caller-supplied original mvhd timescale (from source file before FFmpeg ran).
        /// When set and different from movieTimescale, the mvhd timescale field is patched
        /// back and all movie-timescale-denominated durations are recomputed.
        let originalMovieTimescale: Int64?

        /// The timescale to use for movie-level duration computations and patches.
        var effectiveMovieTimescale: Int64 {
            originalMovieTimescale ?? movieTimescale
        }

        init(data: Data, fps: Rational, originalMovieTimescale: Int64? = nil) {
            self.data = data
            self.fps = fps
            self.originalMovieTimescale = originalMovieTimescale
        }

        func findMoov() throws {
            // Scan top-level atoms for moov
            var offset = 0
            while offset < data.count - 8 {
                let (atomSize, atomType, _) = try atomHeader(at: offset)
                if atomType == "moov" {
                    try walkMoov(at: offset, size: atomSize)
                    return
                }
                let next = offset + atomSize
                guard next > offset else { throw QTConformerError.malformedAtom }
                offset = next
            }
            throw QTConformerError.noMoovAtom
        }

        // MARK: moov

        func walkMoov(at moovOff: Int, size: Int) throws {
            let (_, _, moovHeader) = try atomHeader(at: moovOff)
            let moovEnd = moovOff + size

            // First pass: read mvhd to get movie timescale
            try walkChildren(parentOff: moovOff + moovHeader, parentEnd: moovEnd) { off, type, childSize, headerSz in
                if type == "mvhd" {
                    let version = data[off + headerSz]
                    movieTimescale = try readInt32(at: off + headerSz + 1 + 3 + (version == 1 ? 16 : 8))
                }
            }

            // Second pass: process trak children (find video track)
            try walkChildren(parentOff: moovOff + moovHeader, parentEnd: moovEnd) { off, type, childSize, headerSz in
                if type == "trak" {
                    if try isVideoTrack(at: off, size: childSize) {
                        try walkVideoTrak(at: off, size: childSize, moovEnd: moovEnd)
                    }
                }
            }

            // Third pass: patch mvhd duration
            try walkChildren(parentOff: moovOff + moovHeader, parentEnd: moovEnd) { off, type, childSize, headerSz in
                if type == "mvhd" {
                    try patchMvhd(at: off, headerSize: headerSz)
                }
            }
        }

        // MARK: Track identification

        func isVideoTrack(at trakOff: Int, size: Int) throws -> Bool {
            let (_, _, trakHeader) = try atomHeader(at: trakOff)
            var result = false
            try walkChildren(parentOff: trakOff + trakHeader, parentEnd: trakOff + size) { off, type, childSize, headerSz in
                if type == "mdia" {
                    let (_, _, mdiaHeader) = try atomHeader(at: off)
                    try walkChildren(parentOff: off + mdiaHeader, parentEnd: off + childSize) { mOff, mType, mSize, mHeader in
                        if mType == "hdlr" {
                            // hdlr: ver+flags(4) + pre_defined(4) → handler_type at +8
                            let handlerTypeOff = mOff + mHeader + 4 + 4
                            if handlerTypeOff + 4 <= data.count {
                                let handlerType = String(bytes: data[handlerTypeOff..<handlerTypeOff+4], encoding: .isoLatin1) ?? ""
                                if handlerType == "vide" { result = true }
                            }
                        }
                    }
                }
            }
            return result
        }

        // MARK: trak (video)

        func walkVideoTrak(at trakOff: Int, size: Int, moovEnd: Int) throws {
            let (_, _, trakHeader) = try atomHeader(at: trakOff)
            let trakEnd = trakOff + size

            // Pass 1: read mediaTimescale from mdhd
            try walkChildren(parentOff: trakOff + trakHeader, parentEnd: trakEnd) { off, type, childSize, headerSz in
                if type == "mdia" {
                    try walkMdia(at: off, size: childSize)
                }
            }

            // Compute newDelta + the mdhd timescale we'll write.
            // If the source mediaTimescale doesn't yield an integer delta for the target
            // rational, switch the mdhd timescale to fps.num so delta = fps.den (e.g.
            // a 48-timescale source conforming to 48000/1001 → new timescale 48000, delta 1001).
            guard mediaTimescale > 0 else { throw QTConformerError.missingAtom("mdhd timescale") }
            let rawDelta = Double(mediaTimescale) * Double(fps.den) / Double(fps.num)
            if rawDelta > 0, rawDelta.truncatingRemainder(dividingBy: 1) == 0 {
                newMediaTimescale = mediaTimescale
                newDelta = Int64(rawDelta)
            } else {
                newMediaTimescale = fps.num
                newDelta = fps.den
            }

            // Pass 2: read stts to compute totalSamples and newMediaDuration BEFORE patching.
            // mdhd appears before minf in the atom tree, so patchMdhd would run with
            // newMediaDuration=0 if we don't pre-compute it here.
            try walkChildren(parentOff: trakOff + trakHeader, parentEnd: trakEnd) { off, type, childSize, headerSz in
                if type == "mdia" {
                    try readSttsSamples(at: off, size: childSize)
                }
            }
            guard newMediaDuration > 0 else { throw QTConformerError.missingAtom("stts") }

            // Pass 3: patch stts deltas, mdhd duration, tkhd duration (newMediaDuration is now set)
            try walkChildren(parentOff: trakOff + trakHeader, parentEnd: trakEnd) { off, type, childSize, headerSz in
                if type == "mdia" {
                    try patchMdiaAtoms(at: off, size: childSize)
                }
            }

            // tkhd
            try walkChildren(parentOff: trakOff + trakHeader, parentEnd: trakEnd) { off, type, childSize, headerSz in
                if type == "tkhd" {
                    try patchTkhd(at: off, headerSize: headerSz)
                }
            }

            // edts/elst (optional)
            try walkChildren(parentOff: trakOff + trakHeader, parentEnd: trakEnd) { off, type, childSize, headerSz in
                if type == "edts" {
                    let (_, _, edtsHeader) = try atomHeader(at: off)
                    try walkChildren(parentOff: off + edtsHeader, parentEnd: off + childSize) { eOff, eType, eSize, eHeader in
                        if eType == "elst" {
                            try patchElst(at: eOff, headerSize: eHeader)
                        }
                    }
                }
            }
        }

        // MARK: mdia (first pass — just timescale)

        func walkMdia(at mdiaOff: Int, size: Int) throws {
            let (_, _, mdiaHeader) = try atomHeader(at: mdiaOff)
            try walkChildren(parentOff: mdiaOff + mdiaHeader, parentEnd: mdiaOff + size) { off, type, childSize, headerSz in
                if type == "mdhd" {
                    let version = data[off + headerSz]
                    // timescale offset depends on version
                    // v0: ver+flags(4) + ctime(4) + mtime(4) → at +12
                    // v1: ver+flags(4) + ctime(8) + mtime(8) → at +20
                    let tsOff = off + headerSz + (version == 1 ? 20 : 12)
                    mediaTimescale = try readInt32(at: tsOff)
                }
            }
        }

        // MARK: mdia (second pass — read stts sample count without patching)

        func readSttsSamples(at mdiaOff: Int, size: Int) throws {
            let (_, _, mdiaHeader) = try atomHeader(at: mdiaOff)
            try walkChildren(parentOff: mdiaOff + mdiaHeader, parentEnd: mdiaOff + size) { off, type, childSize, headerSz in
                if type == "minf" {
                    let (_, _, minfHeader) = try atomHeader(at: off)
                    try walkChildren(parentOff: off + minfHeader, parentEnd: off + childSize) { sOff, sType, sSize, sHeader in
                        if sType == "stbl" {
                            let (_, _, stblHeader) = try atomHeader(at: sOff)
                            try walkChildren(parentOff: sOff + stblHeader, parentEnd: sOff + sSize) { tOff, tType, _, tHeader in
                                if tType == "stts" {
                                    let base = tOff + tHeader + 4  // skip ver+flags
                                    let entryCount = Int(try readUInt32(at: base))
                                    guard entryCount >= 1 && entryCount <= 2 else {
                                        throw QTConformerError.vfrContent(entryCount: entryCount)
                                    }
                                    var sampleTotal: Int64 = 0
                                    for i in 0..<entryCount {
                                        sampleTotal += Int64(try readUInt32(at: base + 4 + i * 8))
                                    }
                                    totalSamples = sampleTotal
                                    newMediaDuration = totalSamples * newDelta
                                }
                            }
                        }
                    }
                }
            }
        }

        // MARK: mdia (third pass — patch atoms)

        func patchMdiaAtoms(at mdiaOff: Int, size: Int) throws {
            let (_, _, mdiaHeader) = try atomHeader(at: mdiaOff)
            try walkChildren(parentOff: mdiaOff + mdiaHeader, parentEnd: mdiaOff + size) { off, type, childSize, headerSz in
                if type == "mdhd" {
                    try patchMdhd(at: off, headerSize: headerSz)
                } else if type == "minf" {
                    try walkMinf(at: off, size: childSize)
                }
            }
        }

        func walkMinf(at minfOff: Int, size: Int) throws {
            let (_, _, minfHeader) = try atomHeader(at: minfOff)
            try walkChildren(parentOff: minfOff + minfHeader, parentEnd: minfOff + size) { off, type, childSize, headerSz in
                if type == "stbl" {
                    try walkStbl(at: off, size: childSize)
                }
            }
        }

        func walkStbl(at stblOff: Int, size: Int) throws {
            let (_, _, stblHeader) = try atomHeader(at: stblOff)
            try walkChildren(parentOff: stblOff + stblHeader, parentEnd: stblOff + size) { off, type, childSize, headerSz in
                if type == "stts" {
                    try patchStts(at: off, headerSize: headerSz)
                }
            }
        }

        // MARK: Atom patching

        func patchStts(at off: Int, headerSize: Int) throws {
            // Layout: version+flags(4) + entry_count(4) + N × [sample_count(4) + sample_delta(4)]
            let base = off + headerSize + 4  // skip ver+flags
            let entryCount = Int(try readUInt32(at: base))
            guard entryCount >= 1 && entryCount <= 2 else {
                throw QTConformerError.vfrContent(entryCount: entryCount)
            }

            var sampleTotal: Int64 = 0
            for i in 0..<entryCount {
                let entryBase = base + 4 + i * 8
                let sampleCount = Int64(try readUInt32(at: entryBase))
                sampleTotal += sampleCount
                // Patch the delta (bytes 4–7 of the entry)
                appendUInt32Patch(at: entryBase + 4, value: UInt32(newDelta))
            }
            totalSamples = sampleTotal
            newMediaDuration = totalSamples * newDelta
        }

        func patchMdhd(at off: Int, headerSize: Int) throws {
            let version = data[off + headerSize]
            // v0: ver+flags(4) + ctime(4) + mtime(4) + timescale(4) + duration(4)
            // v1: ver+flags(4) + ctime(8) + mtime(8) + timescale(4) + duration(8)
            if version == 0 {
                let tsOff  = off + headerSize + 4 + 4 + 4          // timescale field
                let durOff = off + headerSize + 4 + 4 + 4 + 4      // duration field
                if newMediaTimescale != mediaTimescale {
                    appendUInt32Patch(at: tsOff, value: UInt32(newMediaTimescale))
                }
                appendUInt32Patch(at: durOff, value: UInt32(newMediaDuration))
            } else {
                let tsOff  = off + headerSize + 4 + 8 + 8          // timescale field
                let durOff = off + headerSize + 4 + 8 + 8 + 4      // duration field
                if newMediaTimescale != mediaTimescale {
                    appendUInt32Patch(at: tsOff, value: UInt32(newMediaTimescale))
                }
                appendUInt64Patch(at: durOff, value: UInt64(newMediaDuration))
            }
        }

        func patchTkhd(at off: Int, headerSize: Int) throws {
            guard movieTimescale > 0 else { throw QTConformerError.missingAtom("mvhd timescale") }
            let tkhdDur = newMediaDuration * effectiveMovieTimescale / newMediaTimescale
            let version = data[off + headerSize]
            if version == 0 {
                // ver+flags(4) + ctime(4) + mtime(4) + trackID(4) + reserved(4) + duration(4)
                let durOff = off + headerSize + 4 + 4 + 4 + 4 + 4
                appendUInt32Patch(at: durOff, value: UInt32(tkhdDur))
            } else {
                // ver+flags(4) + ctime(8) + mtime(8) + trackID(4) + reserved(4) + duration(8)
                let durOff = off + headerSize + 4 + 8 + 8 + 4 + 4
                appendUInt64Patch(at: durOff, value: UInt64(tkhdDur))
            }
        }

        func patchMvhd(at off: Int, headerSize: Int) throws {
            guard movieTimescale > 0, mediaTimescale > 0 else { return }
            let mvhdDur = newMediaDuration * effectiveMovieTimescale / newMediaTimescale
            let version = data[off + headerSize]
            if version == 0 {
                // ver+flags(4) + ctime(4) + mtime(4) + timescale(4) + duration(4)
                let tsOff  = off + headerSize + 4 + 4 + 4          // timescale field
                let durOff = off + headerSize + 4 + 4 + 4 + 4      // duration field
                // Restore original timescale if FFmpeg changed it
                if let orig = originalMovieTimescale, orig != movieTimescale {
                    appendUInt32Patch(at: tsOff, value: UInt32(orig))
                }
                appendUInt32Patch(at: durOff, value: UInt32(mvhdDur))
            } else {
                // ver+flags(4) + ctime(8) + mtime(8) + timescale(4) + duration(8)
                let tsOff  = off + headerSize + 4 + 8 + 8          // timescale field
                let durOff = off + headerSize + 4 + 8 + 8 + 4      // duration field
                if let orig = originalMovieTimescale, orig != movieTimescale {
                    appendUInt32Patch(at: tsOff, value: UInt32(orig))
                }
                appendUInt64Patch(at: durOff, value: UInt64(mvhdDur))
            }
        }

        func patchElst(at off: Int, headerSize: Int) throws {
            // Layout: ver+flags(4) + entry_count(4) + N entries
            // v0 entry: segDur(4) + mediaTime(4) + rate(4) = 12 bytes
            // v1 entry: segDur(8) + mediaTime(8) + rate(4) = 20 bytes
            guard movieTimescale > 0, mediaTimescale > 0 else { return }
            let newSegDurV0 = UInt32(newMediaDuration * effectiveMovieTimescale / newMediaTimescale)
            let newSegDurV1 = UInt64(newMediaDuration * effectiveMovieTimescale / newMediaTimescale)

            let version = data[off + headerSize]
            let base = off + headerSize + 4  // skip ver+flags
            let entryCount = Int(try readUInt32(at: base))
            let entryStride = version == 1 ? 20 : 12

            for i in 0..<entryCount {
                let entryBase = base + 4 + i * entryStride
                if version == 0 {
                    // Check mediaTime (int32, signed): only patch if >= 0 (not an empty edit)
                    let mediaTime = Int32(bitPattern: try readUInt32(at: entryBase + 4))
                    if mediaTime >= 0 {
                        appendUInt32Patch(at: entryBase, value: newSegDurV0)
                    }
                } else {
                    let mediaTime = Int64(bitPattern: try readUInt64(at: entryBase + 8))
                    if mediaTime >= 0 {
                        appendUInt64Patch(at: entryBase, value: newSegDurV1)
                    }
                }
            }
        }

        // MARK: - Atom header parsing

        /// Returns (fullAtomSize, typeString, headerSize).
        /// headerSize is the number of bytes before the atom's content (size+type, or extended).
        func atomHeader(at offset: Int) throws -> (size: Int, type: String, headerSize: Int) {
            guard offset + 8 <= data.count else { throw QTConformerError.malformedAtom }
            let rawSize = Int(try readUInt32(at: offset))
            let typeBytes = data[offset+4..<offset+8]
            let type = String(bytes: typeBytes, encoding: .isoLatin1) ?? "????"

            if rawSize == 1 {
                // Extended 64-bit size
                guard offset + 16 <= data.count else { throw QTConformerError.malformedAtom }
                let extSize = Int(try readUInt64(at: offset + 8))
                return (extSize, type, 16)
            } else if rawSize == 0 {
                // Extends to end of file
                return (data.count - offset, type, 8)
            } else {
                return (rawSize, type, 8)
            }
        }

        // MARK: - Child walker

        /// Iterates direct children of a container atom, calling `body` for each.
        func walkChildren(
            parentOff: Int,
            parentEnd: Int,
            body: (_ offset: Int, _ type: String, _ size: Int, _ headerSize: Int) throws -> Void
        ) throws {
            var cursor = parentOff
            while cursor < parentEnd - 7 {
                let (childSize, childType, childHeader) = try atomHeader(at: cursor)
                guard childSize >= 8 else { throw QTConformerError.malformedAtom }
                try body(cursor, childType, childSize, childHeader)
                let next = cursor + childSize
                guard next > cursor else { throw QTConformerError.malformedAtom }
                cursor = next
            }
        }

        // MARK: - Patch accumulation

        func appendUInt32Patch(at offset: Int, value: UInt32) {
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes[0] = UInt8((value >> 24) & 0xFF)
            bytes[1] = UInt8((value >> 16) & 0xFF)
            bytes[2] = UInt8((value >>  8) & 0xFF)
            bytes[3] = UInt8( value        & 0xFF)
            patches.append(Patch(offset: offset, bytes: bytes))
        }

        func appendUInt64Patch(at offset: Int, value: UInt64) {
            var bytes = [UInt8](repeating: 0, count: 8)
            bytes[0] = UInt8((value >> 56) & 0xFF)
            bytes[1] = UInt8((value >> 48) & 0xFF)
            bytes[2] = UInt8((value >> 40) & 0xFF)
            bytes[3] = UInt8((value >> 32) & 0xFF)
            bytes[4] = UInt8((value >> 24) & 0xFF)
            bytes[5] = UInt8((value >> 16) & 0xFF)
            bytes[6] = UInt8((value >>  8) & 0xFF)
            bytes[7] = UInt8( value        & 0xFF)
            patches.append(Patch(offset: offset, bytes: bytes))
        }

        // MARK: - Big-endian readers

        func readUInt32(at offset: Int) throws -> UInt32 {
            guard offset + 4 <= data.count else { throw QTConformerError.malformedAtom }
            return UInt32(data[offset]) << 24
                 | UInt32(data[offset+1]) << 16
                 | UInt32(data[offset+2]) << 8
                 | UInt32(data[offset+3])
        }

        func readUInt64(at offset: Int) throws -> UInt64 {
            guard offset + 8 <= data.count else { throw QTConformerError.malformedAtom }
            let hi = UInt64(data[offset]) << 56
                   | UInt64(data[offset+1]) << 48
                   | UInt64(data[offset+2]) << 40
                   | UInt64(data[offset+3]) << 32
            let lo = UInt64(data[offset+4]) << 24
                   | UInt64(data[offset+5]) << 16
                   | UInt64(data[offset+6]) << 8
                   | UInt64(data[offset+7])
            return hi | lo
        }

        func readInt32(at offset: Int) throws -> Int64 {
            Int64(try readUInt32(at: offset))
        }
    }

    // MARK: - Patch struct

    private struct Patch {
        let offset: Int
        let bytes: [UInt8]
    }
}

// MARK: - Error types

enum QTConformerError: LocalizedError {
    case noMoovAtom
    case malformedAtom
    case vfrContent(entryCount: Int)
    case incompatibleRate(fps: String, timescale: Int)
    case missingAtom(String)
    case invalidFPS(String)

    var errorDescription: String? {
        switch self {
        case .noMoovAtom:
            return "No moov atom found — not a valid QuickTime/MP4 file."
        case .malformedAtom:
            return "Malformed atom structure in file."
        case .vfrContent(let count):
            return "File appears to have variable frame rate (stts entry_count=\(count)). Only CFR files (≤2 stts entries) are supported."
        case .incompatibleRate(let fps, let timescale):
            return "Frame rate \(fps) is not compatible with the file's media timescale \(timescale) — the resulting sample delta would not be a whole number, which would break playback. Switch the Frame Rate Conform mode to \"Full rewrap (FFmpeg)\" so FFmpeg can renormalise the timescale first."
        case .missingAtom(let name):
            return "Required atom '\(name)' was not found in the file."
        case .invalidFPS(let s):
            return "Could not parse frame rate '\(s)'. Use integer (e.g. '24'), rational (e.g. '24000/1001'), or known decimal (e.g. '23.976')."
        }
    }
}
