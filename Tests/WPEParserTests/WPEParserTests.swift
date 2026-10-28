import XCTest
import Foundation
@testable import WPEParser

final class WPEParserTests: XCTestCase {
    // MARK: Helpers

    func le32(_ v: UInt32) -> Data {
        withUnsafeBytes(of: v.littleEndian) { Data($0) }
    }

    /// Fixture matching the layout confirmed against real workshop files:
    /// [u32 verLen]["PKGV0022"][u32 entryCount][u32 pathLen][path][u32 offset][u32 size]... [data]
    /// Offsets are relative to the end of the entry table.
    func buildPkg(entries: [(String, Data)]) -> Data {
        let version = "PKGV0022"
        var header = le32(UInt32(version.utf8.count)) + Data(version.utf8) + le32(UInt32(entries.count))

        let tableSize = entries.reduce(0) { $0 + 4 + $1.0.utf8.count + 8 }
        let dataStart = header.count + tableSize

        var table = Data()
        var payloadBlob = Data()
        var running = UInt32(0)
        for (name, payload) in entries {
            table += le32(UInt32(name.utf8.count)) + Data(name.utf8)
            table += le32(running)
            table += le32(UInt32(payload.count))
            payloadBlob += payload
            running += UInt32(payload.count)
        }

        header += table + payloadBlob
        return header
    }

    // MARK: LZ4

    func testLZ4LiteralOnlyBlock() {
        // A block encoded as a single literal token (valid LZ4 block data)
        let payload = Array("hello lz4 block".utf8)
        XCTAssertLessThan(payload.count, 15) // fits in one token nibble
        var block: [UInt8] = [UInt8(payload.count) << 4]
        block.append(contentsOf: payload)
        XCTAssertEqual(try? LZ4.decompress(block), payload)
    }

    func testLZ4OverlappingMatch() {
        // Literal "a", then match offset 1 / length 6 -> run of 7 a's
        let block: [UInt8] = [0x10, UInt8(ascii: "a"), 0x01, 0x00]
        XCTAssertEqual(try? LZ4.decompress(block), Array(repeating: UInt8(ascii: "a"), count: 7))
    }

    func testLZ4RejectsBadOffset() {
        XCTAssertThrowsError(try LZ4.decompress([0x10, 0x61, 0x05, 0x00]))
    }

    func testLZ4RejectsOversizedOutput() {
        // A literal run claiming ~10 MB output must hit the cap when the
        // caller tightens maxOutputSize (hostile-file allocation guard).
        var block: [UInt8] = [0xF0]                 // token: literal length 15 -> extended
        block.append(contentsOf: [0xFF, 0xFF, 0xFF, 0x01]) // + 255*3 + 1 = 766... extended chain
        block.append(contentsOf: Array(repeating: UInt8(0x41), count: 1024))
        XCTAssertThrowsError(try LZ4.decompress(block, maxOutputSize: 64))
    }

    // MARK: PKG

    func testPkgExtractRejectsTraversalPaths() throws {
        // A hostile .pkg entry path containing "../" must be refused, never
        // written outside the extraction directory (zip-slip).
        let pkg = buildPkg(entries: [("../evil.txt", Data([0x01, 0x02]))])
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wpe-slip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pkgFile = dir.appendingPathComponent("t.pkg")
        try pkg.write(to: pkgFile)

        let archive = try PkgArchive(data: pkg)
        XCTAssertThrowsError(try archive.extractAll(from: pkgFile, to: dir))
        let escaped = dir.deletingLastPathComponent().appendingPathComponent("evil.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
    }

    func testPkgRealWorldLayout() throws {
        let payload = Data("hello wallpaper".utf8)
        let data = buildPkg(entries: [("a/test.txt", payload)])
        let pkg = try PkgArchive(data: data)
        XCTAssertEqual(pkg.version, "PKGV0022")
        XCTAssertEqual(pkg.entries.count, 1)
        XCTAssertEqual(pkg.entries[0].path, "a/test.txt")
        XCTAssertEqual(pkg.entries[0].offset, 0) // relative to dataStart
        XCTAssertEqual(pkg.entries[0].size, UInt32(payload.count))
        // dataStart = 4 + 8 + 4 + (4 + 9 + 8) = 37
        XCTAssertEqual(pkg.dataStart, data.count - payload.count)
        let content = try pkg.data(for: pkg.entries[0], from: data)
        XCTAssertEqual(content, payload)
    }

    func testPkgMultipleEntries() throws {
        let e1 = Data("first".utf8), e2 = Data("second-entry-data".utf8)
        let data = buildPkg(entries: [("x/1.txt", e1), ("y/deep/2.txt", e2)])
        let pkg = try PkgArchive(data: data)
        XCTAssertEqual(pkg.entries.count, 2)
        XCTAssertEqual(pkg.entry(atPath: "y/deep/2.txt")?.size, UInt32(e2.count))
        XCTAssertEqual(try pkg.data(for: pkg.entries[0], from: data), e1)
        XCTAssertEqual(try pkg.data(for: pkg.entries[1], from: data), e2)
    }

    func testPkgRejectsBadVersionString() {
        var data = le32(8) + Data("XXXX0022".utf8) + le32(0)
        data += Data(repeating: 0, count: 16)
        XCTAssertThrowsError(try PkgArchive(data: data))
    }

    func testPkgRejectsOutOfBoundsEntry() {
        // One entry claiming more bytes than the file holds
        var data = le32(8) + Data("PKGV0022".utf8) + le32(1)
        data += le32(9) + Data("a/b.tex".utf8) + le32(0) + le32(999_999)
        XCTAssertThrowsError(try PkgArchive(data: data))
    }

    // MARK: TEX (TEXV0005 — layout confirmed against two real samples)

    func buildTexV0005(format: UInt32, width: UInt32, height: UInt32, blob: Data) -> Data {
        var d = Data("TEXV0005".utf8) + [0]
        d += Data("TEXI0001".utf8) + [0]
        d += le32(format)
        d += le32(2)                  // "unknown" — observed 2 in real files
        d += le32(width) + le32(height)
        d += le32(width) + le32(height)
        d += [0x00, 0x00, 0x00, 0xff] // tail observed in real files
        d += Data("TEXB0004".utf8) + [0]
        d += le32(1)                  // observed 1
        d += le32(.max)               // observed 0xFFFFFFFF
        d += le32(0)                  // observed 0
        d += le32(1)                  // mipCount?
        d += le32(width) + le32(height)
        d += le32(1)                  // mipIndex?
        d += le32(UInt32(width * height)) // uncompressedSize (format 9)
        d += le32(UInt32(blob.count))     // compressedSize
        d += blob
        return d
    }

    func testTexV0005UncompressedBlob() throws {
        let blob = Data(repeating: 0x5A, count: 16) // == w*h -> raw
        let tex = try TexFile(data: buildTexV0005(format: 9, width: 4, height: 4, blob: blob))
        XCTAssertEqual(tex.containerVersion, "TEXV0005")
        XCTAssertEqual(tex.images.count, 1)
        XCTAssertEqual(tex.images[0].width, 4)
        XCTAssertEqual(tex.images[0].height, 4)
        XCTAssertEqual(tex.images[0].format, 9)
        XCTAssertFalse(tex.images[0].isLZ4Compressed)
        XCTAssertEqual(tex.images[0].blobs[0], blob)
    }

    func testTexV0005LZ4Blob() throws {
        let raw = Data(repeating: 0x11, count: 14) // < 15: fits one literal token
        // Single-literal-token LZ4 block; 15 stored bytes < 16 uncompressed (w*h)
        // so the parser's compressed<uncompressed heuristic fires the LZ4 path.
        let lz4 = Data([UInt8(raw.count) << 4]) + raw
        let tex = try TexFile(data: buildTexV0005(format: 9, width: 4, height: 4, blob: lz4))
        XCTAssertTrue(tex.images[0].isLZ4Compressed)
        XCTAssertEqual(tex.images[0].blobs[0], raw)
    }

    func testTexV0005RejectsBadRecord() throws {
        var d = Data("TEXV0005".utf8) + [0]
        d += Data("XXXX0001".utf8) + [0]
        XCTAssertThrowsError(try TexFile(data: d))
    }

    func testTexV0005MultiMipAndTexsRecord() throws {
        // TEXB0003 + untagged continuation mip + TEXS descriptor
        var d = Data("TEXV0005".utf8) + [0]
        d += Data("TEXI0001".utf8) + [0]
        d += le32(0) + le32(2)                       // format 0 (RGBA8), unknown
        d += le32(2) + le32(2) + le32(2) + le32(2)   // dims
        d += [0x00, 0x00, 0x00, 0xff]                // tail
        d += Data("TEXB0003".utf8) + [0]
        d += le32(1) + le32(.max) + le32(3) + le32(2) + le32(2) + le32(1) // 6 u32s
        d += le32(16) + le32(16)                     // uncomp == comp -> raw
        d += Data(repeating: 0x77, count: 16)        // mip 0 payload
        // untagged continuation: [w][h][flags][uncomp][comp]
        d += le32(1) + le32(1) + le32(0) + le32(4) + le32(4)
        d += Data(repeating: 0x88, count: 4)         // mip 1 payload
        // TEXS0003: [count=1][width][height] + 1*32 bytes
        d += Data("TEXS0003".utf8) + [0]
        d += le32(1) + le32(2) + le32(2)
        d += Data(repeating: 0x00, count: 32)

        let tex = try TexFile(data: d)
        XCTAssertEqual(tex.images.count, 1)
        XCTAssertEqual(tex.images[0].blobs.count, 2)
        XCTAssertEqual(tex.images[0].blobs[0], Data(repeating: 0x77, count: 16))
        XCTAssertEqual(tex.images[0].blobs[1], Data(repeating: 0x88, count: 4))
        XCTAssertFalse(tex.images[0].isLZ4Compressed)
    }

    func testTexRejectsBadMagic() {
        XCTAssertThrowsError(try TexFile(data: Data("NOPE!".utf8)))
    }

    // MARK: project.json

    func testProjectJSONPropertiesInGeneral() throws {
        // Real files nest properties under "general" — confirmed 2026-10-28
        let json = """
        {
          "contentrating": "Everyone",
          "file": "scene.json",
          "general": {
            "properties": {
              "schemecolor": {"index": 0, "order": 100, "text": "ui_browse_properties_scheme_color", "type": "color", "value": "0.54 0.8 1"},
              "shake": {"index": 2, "order": 102, "text": "shake", "type": "bool", "value": true},
              "strength": {"fraction": true, "index": 4, "max": 4, "min": 0, "order": 104, "precision": 2, "step": 0.1, "text": "strength", "type": "slider", "value": 1}
            },
            "supportsaudioprocessing": true
          },
          "preview": "preview.gif",
          "title": "Test Wallpaper",
          "type": "scene",
          "version": 1,
          "visibility": "public",
          "workshopid": "3481807485"
        }
        """.data(using: .utf8)!
        let p = try ProjectJSON(data: json)
        XCTAssertEqual(p.type, "scene")
        XCTAssertEqual(p.title, "Test Wallpaper")
        XCTAssertEqual(p.file, "scene.json")
        XCTAssertEqual(p.properties.count, 3)
        XCTAssertEqual(p.properties["schemecolor"]?.type, "color")
        XCTAssertEqual(p.properties["schemecolor"]?.value as? String, "0.54 0.8 1")
        XCTAssertEqual(p.properties["shake"]?.value as? Bool, true)
        XCTAssertEqual(p.properties["strength"]?.fields["max"] as? Int, 4)
        XCTAssertEqual(p.properties["strength"]?.fields["fraction"] as? Bool, true)
        // unmodeled fields survive in raw
        XCTAssertEqual(p.raw["workshopid"] as? String, "3481807485")
    }

    func testProjectJSONRootPropertiesFallback() throws {
        let json = """
        {"type": "video", "file": "bg.mp4", "properties": {"schemecolor": {"type": "color", "value": "1 1 1"}}}
        """.data(using: .utf8)!
        let p = try ProjectJSON(data: json)
        XCTAssertEqual(p.type, "video")
        XCTAssertEqual(p.properties["schemecolor"]?.type, "color")
    }

    func testProjectJSONMissingOptionalFields() throws {
        let p = try ProjectJSON(data: Data("{}".utf8))
        XCTAssertEqual(p.type, "unknown")
        XCTAssertNil(p.title)
        XCTAssertTrue(p.properties.isEmpty)
    }

    func testProjectJSONRejectsNonObjectRoot() {
        XCTAssertThrowsError(try ProjectJSON(data: Data("[1,2,3]".utf8)))
    }
}
