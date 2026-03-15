import Foundation

/// Injects `st3d` (ISOBMFF stereo-3D) and Google Spatial Media `uuid` XMP boxes
/// directly into the video sample entry of an MP4 file.
///
/// YouTube and other VR platforms read these binary boxes — not the moov/udta metadata
/// written by AVFoundation's metadata API — to identify a video as VR/3D content.
///
/// Box tree path: moov → trak (vide) → mdia → minf → stbl → stsd → [avc1|hvc1] ← inject here
enum MP4SpatialTagWriter {

    // MARK: - Public entry point

    static func inject(into url: URL) throws {
        var data = try Data(contentsOf: url)
        guard let moov = findBox("moov", in: data, from: 0, to: data.count) else { return }

        var trakOffset = moov.bodyStart
        while trakOffset < moov.end {
            guard let trak = findBox("trak", in: data, from: trakOffset, to: moov.end) else { break }
            defer { trakOffset = trak.end }

            guard
                let mdia  = findBox("mdia",  in: data, from: trak.bodyStart, to: trak.end),
                isVideoMdia(mdia, in: data),
                let minf  = findBox("minf",  in: data, from: mdia.bodyStart, to: mdia.end),
                let stbl  = findBox("stbl",  in: data, from: minf.bodyStart, to: minf.end),
                let stsd  = findBox("stsd",  in: data, from: stbl.bodyStart, to: stbl.end),
                // stsd FullBox body: version(1)+flags(3)+entry_count(4) = 8 bytes before entries
                let codec = findVideoCodecBox(in: data, from: stsd.bodyStart + 8, to: stsd.end)
            else { continue }

            // Avoid double-injection: child boxes of the codec box start after its 78-byte header
            // (8-byte box header + 70-byte VisualSampleEntry fields)
            let codecChildrenStart = codec.start + 78
            guard codecChildrenStart <= codec.end else { continue }
            if findBox("st3d", in: data, from: codecChildrenStart, to: codec.end) != nil { return }

            // Build payload and insert at the end of the codec box body
            let payload = makeSt3dBox() + makeGSphericalUUIDBox()
            data.insert(contentsOf: payload, at: codec.end)

            // All ancestor boxes that span the insertion point need their sizes updated.
            // Insertion point == codec.end, which is < every ancestor's end and > every ancestor's start,
            // so ancestor size field offsets (== ancestor.start) are unaffected by the insertion.
            let delta = UInt32(payload.count)
            for ancestorStart in [codec.start, stsd.start, stbl.start,
                                  minf.start, mdia.start, trak.start, moov.start] {
                data.writeUInt32BE(data.readUInt32BE(at: ancestorStart) + delta, at: ancestorStart)
            }

            // moov sits before mdat (faststart). Inserting bytes inside moov shifts mdat
            // by `delta`, so every chunk offset in every stco/co64 box must be incremented.
            let newMoovEnd = moov.start + Int(data.readUInt32BE(at: moov.start))
            fixChunkOffsets(in: &data, from: moov.bodyStart, to: newMoovEnd, delta: delta)

            try data.write(to: url)
            return
        }
    }

    // MARK: - Box builders

    private static func makeSt3dBox() -> Data {
        // FullBox header: size(4) + "st3d"(4) + version(1) + flags(3) + stereo_mode(1) = 13 bytes
        // stereo_mode = 2 → left-right SBS
        var d = Data()
        d.appendUInt32BE(13)
        d.append(contentsOf: "st3d".utf8)
        d.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // version + flags
        d.append(0x02)                                   // stereo_mode: left-right
        return d
    }

    private static func makeGSphericalUUIDBox() -> Data {
        // Google Spatial Media UUID: FFCC8263-F855-4A93-8814-587A02521FDD
        let uuid = Data([0xFF, 0xCC, 0x82, 0x63, 0xF8, 0x55, 0x4A, 0x93,
                         0x88, 0x14, 0x58, 0x7A, 0x02, 0x52, 0x1F, 0xDD])
        let xmp = Data("""
            <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
              <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                <rdf:Description rdf:about=""
                    xmlns:GSpherical="http://ns.google.com/videos/1.0/spherical/">
                  <GSpherical:Spherical>true</GSpherical:Spherical>
                  <GSpherical:Stitched>true</GSpherical:Stitched>
                  <GSpherical:ProjectionType>equirectangular</GSpherical:ProjectionType>
                  <GSpherical:StereoMode>left-right</GSpherical:StereoMode>
                </rdf:Description>
              </rdf:RDF>
            </x:xmpmeta>
            <?xpacket end="w"?>
            """.utf8)
        var d = Data()
        d.appendUInt32BE(UInt32(4 + 4 + 16 + xmp.count)) // size + "uuid" + UUID + XMP
        d.append(contentsOf: "uuid".utf8)
        d.append(uuid)
        d.append(xmp)
        return d
    }

    // MARK: - Box navigation

    private struct Box {
        let start: Int
        let size: Int
        var end: Int { start + size }
        var bodyStart: Int { start + 8 }
    }

    private static func findBox(_ type: String, in data: Data, from: Int, to: Int) -> Box? {
        var offset = from
        while offset + 8 <= to {
            let size = Int(data.readUInt32BE(at: offset))
            guard size >= 8, offset + size <= to else { break }
            if data.readFourCC(at: offset + 4) == type { return Box(start: offset, size: size) }
            offset += size
        }
        return nil
    }

    private static let videoCodecTypes: Set<String> = ["avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe", "mhvc"]

    private static func findVideoCodecBox(in data: Data, from: Int, to: Int) -> Box? {
        var offset = from
        while offset + 8 <= to {
            let size = Int(data.readUInt32BE(at: offset))
            guard size >= 8, offset + size <= to else { break }
            if videoCodecTypes.contains(data.readFourCC(at: offset + 4)) { return Box(start: offset, size: size) }
            offset += size
        }
        return nil
    }

    // MARK: - Chunk offset fix

    /// Recursively scans container boxes and increments every entry in `stco`/`co64` by `delta`.
    /// Required after inserting bytes into moov (which precedes mdat): mdat shifts by delta,
    /// but stored chunk offsets still point to pre-insertion positions.
    private static func fixChunkOffsets(in data: inout Data, from: Int, to: Int, delta: UInt32) {
        var offset = from
        while offset + 8 <= to {
            let size = Int(data.readUInt32BE(at: offset))
            guard size >= 8, offset + size <= to else { break }
            let type = data.readFourCC(at: offset + 4)

            switch type {
            case "stco":
                // FullBox: version(1)+flags(3)+entry_count(4) then 4-byte offsets
                let count = Int(data.readUInt32BE(at: offset + 12))
                for i in 0..<count {
                    let p = offset + 16 + i * 4
                    data.writeUInt32BE(data.readUInt32BE(at: p) + delta, at: p)
                }
            case "co64":
                // FullBox: version(1)+flags(3)+entry_count(4) then 8-byte offsets
                let count = Int(data.readUInt32BE(at: offset + 12))
                for i in 0..<count {
                    let p = offset + 16 + i * 8
                    let hi = UInt64(data.readUInt32BE(at: p))
                    let lo = UInt64(data.readUInt32BE(at: p + 4))
                    let newVal = (hi << 32 | lo) + UInt64(delta)
                    data.writeUInt32BE(UInt32(newVal >> 32), at: p)
                    data.writeUInt32BE(UInt32(newVal & 0xFFFFFFFF), at: p + 4)
                }
            case "trak", "mdia", "minf", "stbl", "edts", "udta", "dinf", "meta", "mvex", "moof", "traf":
                fixChunkOffsets(in: &data, from: offset + 8, to: offset + size, delta: delta)
            default:
                break
            }
            offset += size
        }
    }

    /// Returns true if the `mdia` box belongs to a video track (hdlr handler_type == "vide").
    private static func isVideoMdia(_ mdia: Box, in data: Data) -> Bool {
        guard let hdlr = findBox("hdlr", in: data, from: mdia.bodyStart, to: mdia.end) else { return false }
        // hdlr FullBox body: version(1)+flags(3)+pre_defined(4)+handler_type(4)
        let handlerTypeOffset = hdlr.bodyStart + 8
        guard handlerTypeOffset + 4 <= data.count else { return false }
        return data.readFourCC(at: handlerTypeOffset) == "vide"
    }
}

// MARK: - Data helpers

private extension Data {
    func readUInt32BE(at i: Int) -> UInt32 {
        (UInt32(self[i]) << 24) | (UInt32(self[i+1]) << 16) | (UInt32(self[i+2]) << 8) | UInt32(self[i+3])
    }
    mutating func writeUInt32BE(_ v: UInt32, at i: Int) {
        self[i] = UInt8((v >> 24) & 0xFF); self[i+1] = UInt8((v >> 16) & 0xFF)
        self[i+2] = UInt8((v >> 8) & 0xFF); self[i+3] = UInt8(v & 0xFF)
    }
    func readFourCC(at i: Int) -> String {
        String(bytes: [self[i], self[i+1], self[i+2], self[i+3]], encoding: .isoLatin1) ?? "????"
    }
    mutating func appendUInt32BE(_ v: UInt32) {
        append(UInt8((v >> 24) & 0xFF)); append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 8)  & 0xFF)); append(UInt8(v & 0xFF))
    }
}
