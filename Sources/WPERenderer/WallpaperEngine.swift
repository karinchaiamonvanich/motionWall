import Foundation
import QuartzCore

/// Lifecycle contract for a wallpaper backend (video / web / scene).
/// The director owns windows and screens; an engine owns content only.
public protocol WallpaperEngine: AnyObject {
    /// The content layer to embed in the wallpaper window.
    var layer: CALayer { get }
    /// Called after the layer is attached to a window.
    func start()
    /// Stop rendering and release decode resources.
    func stop()
    /// Temporarily suspend playback (occluded / asleep / battery).
    func pause()
    func resume()
    func setMuted(_ muted: Bool)
}

/// Unsupported wallpaper types (e.g. `application`) surface this instead.
public final class UnsupportedWallpaperError: Error, CustomStringConvertible {
    public let wallpaperType: String
    public init(_ wallpaperType: String) { self.wallpaperType = wallpaperType }
    public var description: String {
        "wallpaper type '\(wallpaperType)' is not supported (Windows-only content)"
    }
}
