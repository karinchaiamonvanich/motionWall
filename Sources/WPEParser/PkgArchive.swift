import Foundation

public struct PkgEntry: Equatable {
    public let path: String
    /// Byte offset of the file content, **relative to the end of the entry
    /// table** (see `PkgArchive.dataStart`). Confirmed against real files.
    public let offset: UInt32
    public let size: UInt32
}

/// Reader for Wallpaper Engine `.pkg` containers.
///
/// Layout **confirmed 2026-10-28** against a real workshop file
/// (27/27 entries, all in bounds, data region contiguous):
///
/// ```
/// u32 versionStringLength          (e.g. 8)
/// u8[versionStringLength] version  ("PKGV0022" in current files)
/// u32 entryCount
/// entry × entryCount:
///     u32 pathLength
///     u8[pathLength] path          (UTF-8, '/' separators)
///     u32 offset                   (relative to dataStart)
///     u32 size
/// dataStart = end of entry table; file data is one contiguous blob
/// ```
public struct PkgArchive {
    public let version: String
    public let entries: [PkgEntry]
    /// Absolute file offset where the data blob begins.
    public let dataStart: Int

    public static func load(url: URL) throws -> PkgArchive {
        try PkgArchive(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        var r = BinaryReader(data)
        let verLen = Int(try r.readUInt32())
        guard verLen >= 4, verLen <= 64 else {
            throw ParseError.invalidValue("pkg: implausible version string length \(verLen)")
        }
        version = try r.readFixedSizeString(verLen)
        guard version.hasPrefix("PKGV") else {
            throw ParseError.badMagic(expected: "PKGV0022", actual: version)
        }
        let count = Int(try r.readUInt32())
        guard count > 0, count <= 100_000 else {
            throw ParseError.invalidValue("pkg: implausible entry count \(count)")
        }

        var parsed: [PkgEntry] = []
        parsed.reserveCapacity(count)
        for _ in 0..<count {
            let pathLen = Int(try r.readUInt32())
            guard pathLen > 0, pathLen <= 4096 else {
                throw ParseError.invalidValue("pkg: bad path length \(pathLen) at offset \(r.offset)")
            }
            let pathData = try r.readBytes(pathLen)
            guard let path = String(data: pathData, encoding: .utf8), !path.isEmpty else {
                throw ParseError.invalidValue("pkg: non-UTF8 path at offset \(r.offset)")
            }
            let offset = try r.readUInt32()
            let size = try r.readUInt32()
            guard Int(offset) + Int(size) <= data.count else {
                throw ParseError.invalidValue("pkg: entry \(path) out of bounds (offset \(offset) + size \(size))")
            }
            parsed.append(PkgEntry(path: path, offset: offset, size: size))
        }
        entries = parsed
        dataStart = r.offset
    }

    // MARK: - Access

    public func entry(atPath path: String) -> PkgEntry? {
        entries.first { $0.path == path }
    }

    /// Raw content of an entry, resolved against the .pkg bytes.
    public func data(for entry: PkgEntry, from pkgData: Data) throws -> Data {
        let start = pkgData.startIndex + dataStart + Int(entry.offset)
        let end = start + Int(entry.size)
        guard end <= pkgData.count else {
            throw ParseError.invalidValue("pkg: entry \(entry.path) exceeds data bounds")
        }
        return pkgData.subdata(in: start..<end)
    }

    @discardableResult
    public func extractAll(from pkgURL: URL, to directory: URL) throws -> [URL] {
        let pkgData = try Data(contentsOf: pkgURL)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for entry in entries {
            let content = try data(for: entry, from: pkgData)
            let out = try Self.safeDestination(for: entry.path, in: directory)
            try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Refuse to write through a pre-planted symlink pointing elsewhere.
            if let target = try? fm.destinationOfSymbolicLink(atPath: out.path) {
                throw ParseError.invalidValue("pkg: refusing to overwrite symlink '\(entry.path)' -> \(target)")
            }
            try content.write(to: out)
            written.append(out)
        }
        return written
    }

    /// Resolves an entry path to a destination **inside** `directory`.
    /// Entry paths come from the file being parsed, so they are hostile
    /// input: reject absolute paths, `..`/`.` components, backslashes and
    /// NUL bytes so a crafted .pkg can never write outside the target
    /// folder (zip-slip).
    private static func safeDestination(for path: String, in directory: URL) throws -> URL {
        guard !path.isEmpty,
              !path.contains("\\"),
              !path.contains("\0"),
              !path.hasPrefix("/"),
              !path.hasPrefix("~")
        else {
            throw ParseError.invalidValue("pkg: unsafe entry path '\(path)'")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else {
            throw ParseError.invalidValue("pkg: unsafe entry path '\(path)'")
        }
        var out = directory
        for part in parts { out = out.appendingPathComponent(String(part)) }
        return out
    }
}
