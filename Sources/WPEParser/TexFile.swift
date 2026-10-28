import Foundation

/// Reader for Wallpaper Engine `.tex` textures.
///
/// Two container generations are known:
/// - `TEXV0`   — legacy layout described by older community documentation.
/// - `TEXV0005` — **current** format, confirmed against real workshop files.
///
/// TEXV0005 structure (confirmed 2026-10-28 on two real samples):
/// ```
/// "TEXV0005\0"                       9-byte container magic
/// record × n:
///   "TEXI0001\0"                     image header record
///     u32 format                     pixel format enum (0, 9, ... see spec)
///     u32 unknown                    observed value 2 in both samples
///     u32 width
///     u32 height
///     u32 width                      (repeat — likely largest-mip dims)
///     u32 height                     (repeat)
///     u8[4] tail                     observed `00 00 00 ff` in both samples
///   "TEXB0004\0" / "TEXB0003\0"      blob record (two field-count variants)
///     u32 uncompressedSize           pixel size in native format (see enum)
///     u32 compressedSize             LZ4 block-compressed payload length
///     u8[compressedSize] payload     LZ4 block data (raw when comp == uncomp)
///     ...further mips: UNTAGGED 20-byte headers [w][h][flags][uncomp][comp]
///        + payload (continuation; confirmed across the library)
///   "TEXS0003\0"                     sprite-sheet descriptor (particle sheets)
///     u32 count, u32 width, u32 height, then count × 32 bytes of float
///     UV/rect metadata (hypothesis from one sample + 20-file sweep)
/// ```
/// TEXB0003 = 8 u32s before payload, TEXB0004 = 9 u32s. Format enum locked by
/// uncomp/(w·h) ratio: 0=RGBA8 (4 B/px), 7=BC1 (0.5), 4=1 B/px, 8=2 B/px,
/// 9=1 B/px. See docs/spec-tex.md.
public struct TexFile {
    public struct TexImage {
        public let width: Int
        public let height: Int
        /// Pixel format value from the TEXI record.
        public let format: UInt32
        public let unknown: UInt32
        /// Payloads as stored in the file (still LZ4 when decompression failed/skipped).
        public let storedBlobs: [Data]
        /// Payloads after LZ4 block decompression where it applied.
        public let blobs: [Data]

        public var isLZ4Compressed: Bool {
            !storedBlobs.isEmpty && !blobs.isEmpty && blobs[0].count != storedBlobs[0].count
        }
    }

    public let containerVersion: String   // e.g. "TEXV0005" or "TEXV0"
    public let images: [TexImage]

    public init(data: Data) throws {
        var r = BinaryReader(data)
        let probe = try r.readFixedSizeString(5)
        guard probe == "TEXV0" else {
            throw ParseError.badMagic(expected: "TEXV0005", actual: probe)
        }
        // Modern containers are "TEXV0005\0": digits at 5..7, NUL at 8.
        // (Legacy "TEXV0" continues with a u32 format field instead.)
        let isModern = data.count >= 9
            && (48...57).contains(Int(data[data.startIndex + 5]))
            && (48...57).contains(Int(data[data.startIndex + 6]))
            && (48...57).contains(Int(data[data.startIndex + 7]))
            && data[data.startIndex + 8] == 0
        if isModern {
            r = BinaryReader(data)
            containerVersion = try r.readFixedSizeString(9).trimmingCharacters(in: .init(charactersIn: "\0"))
            images = try TexFile.parseTEXV0005(&r)
        } else {
            r = BinaryReader(data, offset: 5)
            containerVersion = "TEXV0"
            images = try TexFile.parseLegacyTEXV0(&r)
        }
    }

    /// True when the 4 bytes look like a record tag ("TEXI"/"TEXB"/"TEXS").
    /// Safe discriminator: continuation headers start with a u32 width
    /// (< 16384), whose second byte can never be 'E' (0x45).
    private static func isRecordTag(_ d: Data) -> Bool {
        guard d.count == 4 else { return false }
        let b = [UInt8](d)
        return b[0] == UInt8(ascii: "T") && b[1] == UInt8(ascii: "E") && b[2] == UInt8(ascii: "X")
    }

    // MARK: TEXV0005 (current)

    private static func parseTEXV0005(_ r: inout BinaryReader) throws -> [TexImage] {
        var images: [TexImage] = []
        var current: TexImage?
        while !r.isAtEnd {
            let record = try r.readFixedSizeString(9)
            if record.hasPrefix("TEXI") {
                let format = try r.readUInt32()
                let unknown = try r.readUInt32()
                let width = Int(try r.readUInt32())
                let height = Int(try r.readUInt32())
                _ = try r.readUInt32() // width repeat
                _ = try r.readUInt32() // height repeat
                _ = try r.readBytes(4) // tail `00 00 00 ff` (both samples)
                guard width > 0, height > 0, width <= 16384, height <= 16384 else {
                    throw ParseError.invalidValue("tex: bad dims \(width)x\(height)")
                }
                current = TexImage(width: width, height: height, format: format,
                                   unknown: unknown, storedBlobs: [], blobs: [])
                images.append(current!)
            } else if record.hasPrefix("TEXB") {
                let blobVersion = try r.readFixedSizeString(4).trimmingCharacters(in: .init(charactersIn: "\0"))
                guard var img = current else {
                    throw ParseError.invalidValue("tex: TEXB record before any TEXI")
                }
                // Both observed blob versions end with [uncompressedSize][compressedSize]
                // + LZ4 payload; they differ in the fields before:
                //   0004: u32(1), u32(ffffffff), u32(0),  u32(1), w, h, u32(1)
                //   0003: u32(1), u32(ffffffff), u32(3?), w,     h, u32(1)
                // (field semantics from two+33-file sweep; see spec-tex.md)
                switch blobVersion {
                case "0004":
                    _ = try r.readUInt32()          // observed 1
                    _ = try r.readUInt32()          // observed 0xFFFFFFFF
                    _ = try r.readUInt32()          // observed 0
                    _ = try r.readUInt32()          // observed 1
                    _ = try r.readUInt32()          // width
                    _ = try r.readUInt32()          // height
                    _ = try r.readUInt32()          // observed 1
                case "0003":
                    _ = try r.readUInt32()          // observed 1
                    _ = try r.readUInt32()          // observed 0xFFFFFFFF
                    _ = try r.readUInt32()          // observed 3 (mipCount?)
                    _ = try r.readUInt32()          // width
                    _ = try r.readUInt32()          // height
                    _ = try r.readUInt32()          // observed 1
                default:
                    throw ParseError.invalidValue("tex: unknown TEXB version '\(blobVersion)'")
                }
                let uncompressed = Int(try r.readUInt32())
                let compressed = Int(try r.readUInt32())
                guard compressed <= r.remaining else {
                    throw ParseError.truncatedFile(context: "tex blob (\(compressed) bytes at \(r.offset))")
                }
                let stored = try r.readBytes(compressed)
                var pixels = stored
                if compressed < uncompressed,
                   let plain = try? LZ4.decompress([UInt8](stored), hintSize: uncompressed) {
                    pixels = Data(plain)
                }
                img.storedBlobs.append(stored)
                img.blobs.append(pixels)
                current = img
                images[images.count - 1] = img

                // Mip continuation blobs: UNTAGGED [w][h][flags][uncomp][comp]
                // + payload, repeating until the next record tag or EOF.
                while !r.isAtEnd,
                      !(try isRecordTag(r.peekBytes(4))) {
                    _ = try r.readUInt32()              // width
                    _ = try r.readUInt32()              // height
                    _ = try r.readUInt32()              // flags? (0/1)
                    let uncomp = Int(try r.readUInt32())
                    let comp = Int(try r.readUInt32())
                    guard comp <= r.remaining else {
                        throw ParseError.truncatedFile(context: "tex continuation blob (\(comp) bytes at \(r.offset))")
                    }
                    let stored = try r.readBytes(comp)
                    var pixels = stored
                    if comp < uncomp,
                       let plain = try? LZ4.decompress([UInt8](stored), hintSize: uncomp) {
                        pixels = Data(plain)
                    }
                    var img = current!
                    img.storedBlobs.append(stored)
                    img.blobs.append(pixels)
                    current = img
                    images[images.count - 1] = img
                }
            } else if record.hasPrefix("TEXS") {
                // Sprite-sheet descriptor: [count][width][height] + count×32
                // bytes of float UV/rect metadata. Skip — renderer reads it
                // later for particle sheets.
                let count = Int(try r.readUInt32())
                _ = try r.readUInt32()                  // width
                _ = try r.readUInt32()                  // height
                try r.readBytes(count * 32)
            } else {
                throw ParseError.invalidValue("tex: unknown record '\(record)' at offset \(r.offset - 9)")
            }
        }
        guard !images.isEmpty else { throw ParseError.invalidValue("tex: no TEXI records found") }
        return images
    }

    // MARK: TEXV0 (legacy — kept per older community docs; unverified against real files)

    private static func parseLegacyTEXV0(_ r: inout BinaryReader) throws -> [TexImage] {
        _ = try r.readUInt32() // format
        _ = try r.readUInt32() // flags
        var images: [TexImage] = []
        while !r.isAtEnd {
            guard let w = try? r.readUInt32(), let h = try? r.readUInt32(),
                  let len = try? r.readUInt32(),
                  w > 0, h > 0, w <= 16384, h <= 16384, Int(len) <= r.remaining else { break }
            let stored = try r.readBytes(Int(len))
            var pixels = stored
            if Int(len) < Int(w) * Int(h),
               let plain = try? LZ4.decompress([UInt8](stored), hintSize: Int(w) * Int(h)) {
                pixels = Data(plain)
            }
            images.append(TexImage(width: Int(w), height: Int(h), format: 0, unknown: 0,
                                   storedBlobs: [stored], blobs: [pixels]))
        }
        guard !images.isEmpty else { throw ParseError.invalidValue("tex: no images parsed") }
        return images
    }
}
