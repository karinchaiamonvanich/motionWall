import AppKit

/// Borderless window pinned to the desktop, one per screen.
/// Sits just below the desktop-icon layer, above the wallpaper —
/// icons and Dock stay on top and interactive; the window never
/// takes focus, never appears in Mission Control's window cycle.
final class DesktopWallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // One level below desktop icons = above the system wallpaper.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        isOpaque = false
        backgroundColor = .black
        ignoresMouseEvents = true
        hasShadow = false
        contentView?.wantsLayer = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Not part of the normal window cycle / no Window menu entries.
        isExcludedFromWindowsMenu = true
    }

    /// Re-fit when the screen's geometry changes (resolution, arrangement).
    func fit(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }
}
