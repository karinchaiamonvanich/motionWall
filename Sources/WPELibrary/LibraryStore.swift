import Foundation
import WPEParser

/// One wallpaper found in the user's library.
///
/// Not `Equatable`: `ProjectJSON` holds untyped JSON dictionaries
/// (`[String: Any]`). Identity is the folder `id` — compare that instead.
public struct WallpaperItem {
    public let id: String          // folder name (workshop id for Steam content)
    public let url: URL            // wallpaper folder
    public let project: ProjectJSON

    public var isSupported: Bool {
        WallpaperItem.supportedTypes.contains(project.type)
    }

    /// Resolves the entry file (e.g. the .mp4 for video wallpapers).
    public func entryFileURL() -> URL? {
        guard let file = project.file, !file.isEmpty else { return nil }
        let url = self.url.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static let supportedTypes: Set<String> = ["video", "web", "scene"]
}

/// Scans a user-chosen folder (Steam workshop content tree, or any folder of
/// unpacked wallpapers) for items with a `project.json`. No Steam required.
public final class LibraryStore {
    public init() {}

    public func scan(folder: URL) throws -> [WallpaperItem] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [WallpaperItem] = []
        for dir in dirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let projectURL = dir.appendingPathComponent("project.json")
            guard fm.fileExists(atPath: projectURL.path) else { continue }
            do {
                let project = try ProjectJSON(url: projectURL)
                items.append(WallpaperItem(id: dir.lastPathComponent, url: dir, project: project))
            } catch {
                // Broken manifest — skip the item, keep the library usable.
                continue
            }
        }
        return items.sorted { $0.project.title ?? $0.id < $1.project.title ?? $1.id }
    }
}
