import Foundation

public enum ParseError: Error, CustomStringConvertible {
    case truncatedFile(context: String)
    case badMagic(expected: String, actual: String)
    case invalidValue(String)

    public var description: String {
        switch self {
        case .truncatedFile(let c):
            return "file truncated: \(c)"
        case .badMagic(let expected, let actual):
            return "bad magic: expected '\(expected)', found '\(actual)'"
        case .invalidValue(let m):
            return "invalid value: \(m)"
        }
    }
}

/// Little-endian sequential reader over an in-memory Data.
public struct BinaryReader {
    public let data: Data
    public private(set) var offset: Int

    public var remaining: Int { data.count - offset }
    public var isAtEnd: Bool { offset >= data.count }

    public init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    public mutating func readByte() throws -> UInt8 {
        guard offset < data.count else {
            throw ParseError.truncatedFile(context: "byte at offset \(offset)")
        }
        let b = data[data.startIndex + offset]
        offset += 1
        return b
    }

    public mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw ParseError.truncatedFile(context: "\(count) bytes at offset \(offset)")
        }
        let start = data.startIndex + offset
        offset += count
        return data.subdata(in: start..<start + count)
    }

    public mutating func readUInt16() throws -> UInt16 {
        let d = try readBytes(2)
        return UInt16(d[d.startIndex])
            | UInt16(d[d.startIndex + 1]) << 8
    }

    public mutating func readUInt32() throws -> UInt32 {
        let d = try readBytes(4)
        return UInt32(d[d.startIndex])
            | UInt32(d[d.startIndex + 1]) << 8
            | UInt32(d[d.startIndex + 2]) << 16
            | UInt32(d[d.startIndex + 3]) << 24
    }

    public mutating func readUInt64() throws -> UInt64 {
        let lo = try readUInt32()
        let hi = try readUInt32()
        return UInt64(lo) | UInt64(hi) << 32
    }

    /// u32 length prefix + UTF-8 payload. Guard rails against nonsense lengths
    /// so a misaligned table fails fast instead of allocating gigabytes.
    public mutating func readLengthPrefixedString() throws -> String {
        let len = Int(try readUInt32())
        guard len > 0, len <= 4096 else {
            throw ParseError.invalidValue("string length \(len) at offset \(offset - 4) is out of range")
        }
        let d = try readBytes(len)
        return String(data: d, encoding: .utf8) ?? "<invalid utf8>"
    }

    public mutating func readFixedSizeString(_ count: Int) throws -> String {
        let d = try readBytes(count)
        return String(data: d, encoding: .utf8)?
            .trimmingCharacters(in: .init(charactersIn: "\0")) ?? "<invalid utf8>"
    }

    /// Look at bytes ahead without consuming.
    public func peekBytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw ParseError.truncatedFile(context: "peek \(count) bytes at offset \(offset)")
        }
        let start = data.startIndex + offset
        return data.subdata(in: start..<start + count)
    }
}
