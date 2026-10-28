import AppKit
import WPELibrary
import WPERenderer

/// Owns one window + engine per NSScreen and keeps them alive across
/// sleep/wake, occlusion and display-arrangement changes.
///
/// Selection model for M2: one wallpaper applied to every screen. Each screen
/// gets its own engine instance (a CALayer can only live in one window), so
/// multi-monitor playback is independent per screen — perfect sync across
/// screens is a later refinement.
public final class WallpaperDirector {
    private final class ScreenEntry {
        let window: DesktopWallpaperWindow
        let engine: WallpaperEngine

        init(window: DesktopWallpaperWindow, engine: WallpaperEngine) {
            self.window = window
            self.engine = engine
        }
    }

    private var screens: [CGDirectDisplayID: ScreenEntry] = [:]
    private var currentItem: WallpaperItem?
    private var isMuted = true
    private var observers: [NSObjectProtocol] = []

    public var selectedItem: WallpaperItem? { currentItem }

    public init() {
        installObservers()
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        stopAll()
    }

    // MARK: - Applying wallpapers

    /// Build and show the wallpaper on every connected screen.
    public func apply(item: WallpaperItem) throws {
        guard item.isSupported else {
            throw UnsupportedWallpaperError(item.project.type)
        }
        stopAll()
        currentItem = item

        for screen in NSScreen.screens {
            guard let id = displayID(for: screen) else { continue }
            let engine = try Self.makeEngine(for: item, muted: isMuted)
            let window = DesktopWallpaperWindow(screen: screen)
            engine.layer.frame = window.contentView!.bounds
            window.contentView?.layer?.addSublayer(engine.layer)
            window.orderFrontRegardless()
            engine.start()
            screens[id] = ScreenEntry(window: window, engine: engine)
        }
    }

    public func stopAll() {
        for entry in screens.values {
            entry.engine.stop()
            entry.window.orderOut(nil)
        }
        screens.removeAll()
        currentItem = nil
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        for entry in screens.values { entry.engine.setMuted(muted) }
    }

    public func pauseAll() {
        for entry in screens.values { entry.engine.pause() }
    }

    public func resumeAll() {
        for entry in screens.values { entry.engine.resume() }
    }

    // MARK: - Engine construction

    private static func makeEngine(for item: WallpaperItem, muted: Bool) throws -> WallpaperEngine {
        switch item.project.type {
        case "video":
            guard let fileURL = item.entryFileURL() else {
                throw UnsupportedWallpaperError("video (missing entry file)")
            }
            return try VideoWallpaperEngine(fileURL: fileURL, muted: muted)
        case "web":
            // M3 — web backend lands here with the same protocol.
            throw UnsupportedWallpaperError("web (planned for M3)")
        case "scene":
            // M4/M5 — scene renderer.
            throw UnsupportedWallpaperError("scene (planned for M4/M5)")
        default:
            throw UnsupportedWallpaperError(item.project.type)
        }
    }

    // MARK: - Lifecycle observers

    private func installObservers() {
        let nc = NotificationCenter.default

        // Window covered/uncovered → pause/resume decode work.
        observers.append(nc.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let window = note.object as? NSWindow,
                  window is DesktopWallpaperWindow else { return }
            if window.occlusionState.contains(.visible) {
                self.resumeAll()
            } else {
                self.pauseAll()
            }
        })

        let wnc = NSWorkspace.shared.notificationCenter
        observers.append(wnc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.pauseAll() })
        observers.append(wnc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.resumeAll() })

        // Displays connected/disconnected/resolution change → rebuild.
        // (Defined on NSApplication, not NSScreen.)
        observers.append(nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.reapply() })
    }

    private func reapply() {
        guard let item = currentItem else { return }
        try? apply(item: item)
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
