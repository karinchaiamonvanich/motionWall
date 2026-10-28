import Foundation
import WPEParser

// wpe-inspect — M1 exploration CLI.
// Usage:
//   wpe-inspect pkg <file.pkg> [--list] [--extract <dir>] [--json]
//   wpe-inspect tex <file.tex> [--json] [--dump <outfile>]
//   wpe-inspect project <path.json | wallpaper dir>

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(1)
}

func printJSON(_ obj: Any) {
    guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else {
        die("could not serialize summary")
    }
    print(String(decoding: d, as: UTF8.self))
}

func hexdump(_ data: Data, maxBytes: Int = 64) -> [String] {
    var lines: [String] = []
    let n = min(data.count, maxBytes)
    for row in stride(from: 0, to: n, by: 16) {
        let end = min(row + 16, n)
        let hex = data[row..<end].map { String(format: "%02x", $0) }.joined(separator: " ")
        let ascii = data[row..<end].map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
        let paddedHex = hex.padding(toLength: max(hex.count, 47), withPad: " ", startingAt: 0)
        lines.append(String(format: "  %06x  %@  |%@|", row, paddedHex, ascii))
    }
    if data.count > maxBytes {
        lines.append("  ... (\(data.count - maxBytes) more bytes)")
    }
    return lines
}

func cmdPkg(_ args: [String]) {
    guard let path = args.first else { die("pkg: missing file path") }
    let url = URL(fileURLWithPath: path)
    let list = args.contains("--list")
    let extractIdx = args.firstIndex(of: "--extract")
    let asJSON = args.contains("--json")

    let pkgData: Data
    let archive: PkgArchive
    do {
        pkgData = try Data(contentsOf: url)
        archive = try PkgArchive(data: pkgData)
    } catch {
        die("\(error)")
    }

    if asJSON {
        printJSON([
            "version": archive.version,
            "dataStart": archive.dataStart,
            "entryCount": archive.entries.count,
            "entries": archive.entries.map {
                ["path": $0.path, "offset": $0.offset, "size": $0.size]
            },
        ])
        return
    }

    print("version:   \(archive.version)")
    print("dataStart: \(archive.dataStart)")
    print("entries:   \(archive.entries.count)")

    if list {
        for e in archive.entries {
            print(String(format: "  %10u  %9u  %@", e.offset, e.size, e.path))
        }
    }

    if let i = extractIdx, i + 1 < args.count {
        let dir = URL(fileURLWithPath: args[i + 1])
        do {
            let written = try archive.extractAll(from: url, to: dir)
            print("extracted: \(written.count) files -> \(dir.path)")
        } catch {
            die("extract failed: \(error)")
        }
    }
}

func cmdTex(_ args: [String]) {
    guard let path = args.first else { die("tex: missing file path") }
    let asJSON = args.contains("--json")
    let dumpIdx = args.firstIndex(of: "--dump")

    let tex: TexFile
    let raw: Data
    do {
        raw = try Data(contentsOf: URL(fileURLWithPath: path))
        tex = try TexFile(data: raw)
    } catch {
        die("\(error)")
    }

    if asJSON {
        printJSON([
            "containerVersion": tex.containerVersion,
            "imageCount": tex.images.count,
            "images": tex.images.map {
                [
                    "width": $0.width, "height": $0.height,
                    "format": $0.format, "unknown": $0.unknown,
                    "blobCount": $0.blobs.count,
                    "blobSizes": $0.blobs.map { $0.count },
                    "storedSizes": $0.storedBlobs.map { $0.count },
                    "lz4Compressed": $0.isLZ4Compressed,
                ]
            },
        ])
        return
    }

    print("container: \(tex.containerVersion)")
    print("images:    \(tex.images.count)")
    for (i, img) in tex.images.enumerated() {
        print("  [\(i)] \(img.width)x\(img.height)  format=\(img.format)  unknown=\(img.unknown)  blobs=\(img.blobs.count)")
        for (j, b) in img.blobs.enumerated() {
            print("      blob[\(j)] stored=\(img.storedBlobs[j].count)B  pixels=\(b.count)B  lz4=\(img.isLZ4Compressed)")
        }
        if img.blobs.isEmpty {
            print("      (TEXB layout not decoded — raw payload captured, see spec-tex.md)")
        }
    }
    print("header hex (first 64 bytes):")
    for line in hexdump(raw, maxBytes: 64) { print(line) }

    if let i = dumpIdx, i + 1 < args.count, let img = tex.images.first, let blob = img.blobs.first {
        try! blob.write(to: URL(fileURLWithPath: args[i + 1]))
        print("raw pixel payload written to \(args[i + 1])")
    }
}

func cmdProject(_ args: [String]) {
    guard let path = args.first else { die("project: missing path") }
    let url = URL(fileURLWithPath: path)
    let jsonURL: URL
    if url.lastPathComponent == "project.json" {
        jsonURL = url
    } else {
        jsonURL = url.appendingPathComponent("project.json")
    }
    let project: ProjectJSON
    do {
        project = try ProjectJSON(url: jsonURL)
    } catch {
        die("\(error)")
    }

    print("type:        \(project.type)")
    print("title:       \(project.title ?? "<none>")")
    print("file:        \(project.file ?? "<none>")")
    print("rating:      \(project.contentRating ?? "<none>")")
    print("properties:  \(project.properties.count)")
    for (k, p) in project.properties.sorted(by: { ($0.value.order ?? 999) < ($1.value.order ?? 999) }) {
        print("  \(k): type=\(p.type) value=\(p.value.map(String.init(describing:)) ?? "<none>")")
    }
    let modeledKeys: Set<String> = ["type", "title", "file", "contentrating", "preview", "visibleinlibrary", "general"]
    let extra = Set(project.raw.keys).subtracting(modeledKeys).sorted()
    if !extra.isEmpty {
        print("unmodeled fields (please report/extend): \(extra.joined(separator: ", "))")
    }
}

// MARK: - Dispatch

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("""
    wpe-inspect — Wallpaper Engine format inspector (M1, clean-room)

    USAGE:
      wpe-inspect pkg <file.pkg> [--list] [--extract <dir>] [--json]
      wpe-inspect tex <file.tex> [--json] [--dump <outfile>]
      wpe-inspect project <dir-or-project.json>
    """)
    exit(0)
}

switch command {
case "pkg":
    cmdPkg(Array(args.dropFirst()))
case "tex":
    cmdTex(Array(args.dropFirst()))
case "project":
    cmdProject(Array(args.dropFirst()))
default:
    die("unknown command '\(command)'")
}
