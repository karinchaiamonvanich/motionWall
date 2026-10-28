import Foundation

/// Minimal clean-room LZ4 **block** decompressor, written from the public
/// LZ4 block format description (https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md
/// and the block format section of the spec). No LZ4 project code is used.
public enum LZ4 {
    public enum LZ4Error: Error, CustomStringConvertible {
        case outOfInput(String)
        case invalidOffset(UInt32)
        case outputTooLarge(Int)

        public var description: String {
            switch self {
            case .outOfInput(let c): return "lz4: ran out of input: \(c)"
            case .invalidOffset(let o): return "lz4: match offset \(o) exceeds history"
            case .outputTooLarge(let n): return "lz4: output exceeds maxOutputSize (\(n) bytes)"
            }
        }
    }

    /// Decompresses a raw LZ4 block. Output grows until the input is consumed.
    ///
    /// `maxOutputSize` caps how much a single block may expand to — the
    /// `uncompressedSize` field comes from the file itself, so a hostile
    /// file must never be able to request gigabytes of allocation
    /// (allocation/compression-bomb guard). 256 MiB is far above any real
    /// wallpaper mip (4K RGBA8 ≈ 33 MiB).
    public static func decompress(_ input: [UInt8], hintSize: Int? = nil,
                                  maxOutputSize: Int = 256 * 1024 * 1024) throws -> [UInt8] {
        guard maxOutputSize > 0 else { throw LZ4Error.outputTooLarge(Int(maxOutputSize)) }
        var output: [UInt8] = []
        output.reserveCapacity(min(hintSize ?? input.count * 4, maxOutputSize))
        var i = 0

        while i < input.count {
            let token = input[i]
            i += 1

            // Literal length
            var literalLength = Int(token >> 4)
            if literalLength == 15 {
                var b: UInt8 = 15
                repeat {
                    guard i < input.count else { throw LZ4Error.outOfInput("literal length byte") }
                    b = input[i]; i += 1
                    literalLength += Int(b)
                } while b == 255
            }
            guard i + literalLength <= input.count else {
                throw LZ4Error.outOfInput("literal run of \(literalLength)")
            }
            guard output.count + literalLength <= maxOutputSize else {
                throw LZ4Error.outputTooLarge(output.count + literalLength)
            }
            output.append(contentsOf: input[i..<i + literalLength])
            i += literalLength

            // Last token may end after literals only
            if i >= input.count { break }

            // Match offset (2 bytes, little endian, must be > 0)
            guard i + 2 <= input.count else { throw LZ4Error.outOfInput("match offset") }
            let offset = UInt32(input[i]) | UInt32(input[i + 1]) << 8
            i += 2
            guard offset > 0, Int(offset) <= output.count else {
                throw LZ4Error.invalidOffset(offset)
            }

            // Match length: token low nibble + 4, extended by 255-bytes
            var matchLength = Int(token & 0x0F) + 4
            if Int(token & 0x0F) == 15 {
                var b: UInt8 = 15
                repeat {
                    guard i < input.count else { throw LZ4Error.outOfInput("match length byte") }
                    b = input[i]; i += 1
                    matchLength += Int(b)
                } while b == 255
            }
            guard output.count + matchLength <= maxOutputSize else {
                throw LZ4Error.outputTooLarge(output.count + matchLength)
            }

            // Byte-at-a-time copy: overlapping matches (offset < matchLength) are legal
            var pos = output.count - Int(offset)
            for _ in 0..<matchLength {
                output.append(output[pos])
                pos += 1
            }
        }
        return output
    }
}
