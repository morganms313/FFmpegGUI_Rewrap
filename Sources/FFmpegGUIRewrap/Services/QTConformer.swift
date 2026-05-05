import Foundation

/// Patches QuickTime container atoms (stts / mdhd / tkhd / mvhd / elst) to conform the
/// declared frame rate without re-encoding the video or audio bitstream.
///
/// This is equivalent to what tools like cineXmeta do: direct in-place atom surgery on the
/// QuickTime atom tree, touching only the timing fields that players / MediaInfo read.
struct QTConformer {

    // MARK: - Public API

    /// Conform `url` in-place to `targetFPS`.
    ///
    /// - Parameters:
    ///   - url: Path to a `.mov` or `.mp4` file (must be writable).
    ///   - targetFPS: Rational string — `"24"`, `"24000/1001"`, or decimal like `"23.976"`.
    static func conform(url: URL, targetFPS: String) throws {
        // 1. Memory-map the file for efficient parsing.
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        // 2. Parse the FPS into a rational.
        let fps = try parseFPS(targetFPS)

        // 3. Walk the atom tree and collect patches.
        var ctx = ConformContext(data: data, fps: fps)
        try ctx.findMoov()

        // 4. Apply all patches via FileHandle.
        let fh = try FileHandle(forUpdating: url)
        defer { try? fh.close() }
        for patch in ctx.patches.sorted(by: { $0.offset < $1.offset }) {
            try fh.seek(toOffset: UInt64(patch.offset))
            fh.write(Data(patch.bytes))
        }
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

    private struct ConformContext {
        let data: Data
        let fps: Rational
        var patches: [Patch] = []

        // Collected from the video track's mdhd
        var mediaTimescale: Int64 = 0
        var newDelta: Int64 = 0          // mediaTimescale * den / num  (must be integer)
        var totalSamples: Int64 = 0
        var newMediaDuration: Int64 = 0  // totalSamples * newDelta
        var movieTimescale: Int64 = 0

        mutating func findMoov() throws {
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

        mutating func walkMoov(at moovOff: Int, size: Int) throws {
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
                            // hdlr: ver+flags(4) + pre_defined(4) + handler_type(4)
                            let handlerTypeOff = mOff + mHeader + 4 + 4 + 4
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

        mutating func walkVideoTrak(at trakOff: Int, size: Int, moovEnd: Int) throws {
            let (_, _, trakHeader) = try atomHeader(at: trakOff)
            let trakEnd = trakOff + size

            // Walk mdia to get timescale + patch mdhd + patch stts
            try walkChildren(parentOff: trakOff + trakHeader, parentEnd: trakEnd) { off, type, childSize, headerSz in
                if type == "mdia" {
                    try walkMdia(at: off, size: childSize)
                }
            }

            // Compute new delta now that we have mediaTimescale
            guard mediaTimescale > 0 else { throw QTConformerError.missingAtom("mdhd timescale") }
            let rawDelta = Double(mediaTimescale) * Double(fps.den) / Double(fps.num)
            guard rawDelta.truncatingRemainder(dividingBy: 1) == 0, rawDelta > 0 else {
                throw QTConformerError.incompatibleRate(
                    fps: "\(fps.num)/\(fps.den)", timescale: Int(mediaTimescale))
            }
            newDelta = Int64(rawDelta)

            // Now patch stts (needs newDelta), mdhd duration, tkhd duration
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

        mutating func walkMdia(at mdiaOff: Int, size: Int) throws {
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

        // MARK: mdia (second pass — patch atoms)

        mutating func patchMdiaAtoms(at mdiaOff: Int, size: Int) throws {
            let (_, _, mdiaHeader) = try atomHeader(at: mdiaOff)
            try walkChildren(parentOff: mdiaOff + mdiaHeader, parentEnd: mdiaOff + size) { off, type, childSize, headerSz in
                if type == "mdhd" {
                    try patchMdhd(at: off, headerSize: headerSz)
                } else if type == "minf" {
                    try walkMinf(at: off, size: childSize)
                }
            }
        }

        mutating func walkMinf(at minfOff: Int, size: Int) throws {
            let (_, _, minfHeader) = try atomHeader(at: minfOff)
            try walkChildren(parentOff: minfOff + minfHeader, parentEnd: minfOff + size) { off, type, childSize, headerSz in
                if type == "stbl" {
                    try walkStbl(at: off, size: childSize)
                }
            }
        }

        mutating func walkStbl(at stblOff: Int, size: Int) throws {
            let (_, _, stblHeader) = try atomHeader(at: stblOff)
            try walkChildren(parentOff: stblOff + stblHeader, parentEnd: stblOff + size) { off, type, childSize, headerSz in
                if type == "stts" {
                    try patchStts(at: off, headerSize: headerSz)
                }
            }
        }

        // MARK: Atom patching

        mutating func patchStts(at off: Int, headerSize: Int) throws {
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

        mutating func patchMdhd(at off: Int, headerSize: Int) throws {
            let version = data[off + headerSize]
            // v0: ver+flags(4) + ctime(4) + mtime(4) + timescale(4) + duration(4)
            // v1: ver+flags(4) + ctime(8) + mtime(8) + timescale(4) + duration(8)
            if version == 0 {
                let durOff = off + headerSize + 4 + 4 + 4 + 4  // skip ver+flags, ctime, mtime, timescale
                appendUInt32Patch(at: durOff, value: UInt32(newMediaDuration))
            } else {
                let durOff = off + headerSize + 4 + 8 + 8 + 4  // skip ver+flags, ctime, mtime, timescale
                appendUInt64Patch(at: durOff, value: UInt64(newMediaDuration))
            }
        }

        mutating func patchTkhd(at off: Int, headerSize: Int) throws {
            guard movieTimescale > 0 else { throw QTConformerError.missingAtom("mvhd timescale") }
            let tkhdDur = newMediaDuration * movieTimescale / mediaTimescale
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

        mutating func patchMvhd(at off: Int, headerSize: Int) throws {
            guard movieTimescale > 0, mediaTimescale > 0 else { return }
            let mvhdDur = newMediaDuration * movieTimescale / mediaTimescale
            let version = data[off + headerSize]
            if version == 0 {
                // ver+flags(4) + ctime(4) + mtime(4) + timescale(4) + duration(4)
                let durOff = off + headerSize + 4 + 4 + 4 + 4
                appendUInt32Patch(at: durOff, value: UInt32(mvhdDur))
            } else {
                // ver+flags(4) + ctime(8) + mtime(8) + timescale(4) + duration(8)
                let durOff = off + headerSize + 4 + 8 + 8 + 4
                appendUInt64Patch(at: durOff, value: UInt64(mvhdDur))
            }
        }

        mutating func patchElst(at off: Int, headerSize: Int) throws {
            // Layout: ver+flags(4) + entry_count(4) + N entries
            // v0 entry: segDur(4) + mediaTime(4) + rate(4) = 12 bytes
            // v1 entry: segDur(8) + mediaTime(8) + rate(4) = 20 bytes
            guard movieTimescale > 0, mediaTimescale > 0 else { return }
            let newSegDurV0 = UInt32(newMediaDuration * movieTimescale / mediaTimescale)
            let newSegDurV1 = UInt64(newMediaDuration * movieTimescale / mediaTimescale)

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

        mutating func appendUInt32Patch(at offset: Int, value: UInt32) {
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes[0] = UInt8((value >> 24) & 0xFF)
            bytes[1] = UInt8((value >> 16) & 0xFF)
            bytes[2] = UInt8((value >>  8) & 0xFF)
            bytes[3] = UInt8( value        & 0xFF)
            patches.append(Patch(offset: offset, bytes: bytes))
        }

        mutating func appendUInt64Patch(at offset: Int, value: UInt64) {
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
            return "Frame rate \(fps) is not compatible with media timescale \(timescale) — the resulting sample delta is not an integer."
        case .missingAtom(let name):
            return "Required atom '\(name)' was not found in the file."
        case .invalidFPS(let s):
            return "Could not parse frame rate '\(s)'. Use integer (e.g. '24'), rational (e.g. '24000/1001'), or known decimal (e.g. '23.976')."
        }
    }
}
