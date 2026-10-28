import Foundation

public struct WPEProperty {
    /// All keys in the property object (order, text, type, value, index,
    /// fraction, min, max, step, precision, options, ...) preserved as-is.
    public let fields: [String: Any]

    public var type: String { fields["type"] as? String ?? "unknown" }
    public var order: Int? { fields["order"] as? Int }
    public var text: String? { fields["text"] as? String }
    public var value: Any? { fields["value"] }
}

/// Reader for `project.json`, the manifest at the root of every wallpaper.
///
/// Confirmed against real files (2026-10-28): user-adjustable properties live
/// under `general.properties` (a root-level `properties` is kept as fallback
/// for robustness). Unknown fields are preserved in `raw`.
public struct ProjectJSON {
    /// scene | video | web | application
    public let type: String
    public let title: String?
    /// Entry file: scene.json, .mp4, index.html — depends on `type`.
    public let file: String?
    public let contentRating: String?
    public let preview: String?
    public let visibleInLibrary: Bool?
    /// Confirmed: properties live inside `general` for real wallpapers.
    public let general: [String: Any]
    public let properties: [String: WPEProperty]
    public let raw: [String: Any]

    public init(data: Data) throws {
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let d = obj as? [String: Any] else {
            throw ParseError.invalidValue("project.json: root must be a JSON object")
        }
        raw = d
        type = d["type"] as? String ?? "unknown"
        title = d["title"] as? String
        file = d["file"] as? String
        contentRating = d["contentrating"] as? String
        preview = d["preview"] as? String
        visibleInLibrary = d["visibleinlibrary"] as? Bool
        general = d["general"] as? [String: Any] ?? [:]

        // Confirmed location (real files), with root-level fallback.
        let propDict = (general["properties"] as? [String: Any])
            ?? (d["properties"] as? [String: Any]) ?? [:]
        var props: [String: WPEProperty] = [:]
        for (key, v) in propDict {
            guard let fields = v as? [String: Any] else { continue }
            props[key] = WPEProperty(fields: fields)
        }
        properties = props
    }

    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }
}
