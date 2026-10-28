import AppKit
import WPELibrary
import WPERenderer

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let library = LibraryStore()
    private let director = WallpaperDirector()
    private var items: [WallpaperItem] = []
    private var statusItem: NSStatusItem!

    private enum Prefs {
        static let libraryPath = "libraryPath"
        static let lastWallpaperID = "lastWallpaperID"
        static let muted = "muted"
    }
    private var defaults: UserDefaults { .standard }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        statusItem.button?.image = NSImage(
            systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Wallpaper")

        loadLibrary()
    }

    // MARK: - Menu (rebuilt on every open)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let choose = NSMenuItem(title: "Choose Library Folder…",
                                action: #selector(chooseLibrary(_:)), keyEquivalent: "o")
        choose.target = self
        menu.addItem(choose)

        if let path = defaults.string(forKey: Prefs.libraryPath) {
            let label = NSMenuItem(title: "Library: \(lastPathComponent(path))",
                                   action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
        }

        menu.addItem(.separator())

        let videoItems = items.filter { $0.project.type == "video" }
        if videoItems.isEmpty {
            let none = NSMenuItem(title: "No video wallpapers found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for (i, item) in videoItems.enumerated() {
                let selected = director.selectedItem?.id == item.id
                let mi = NSMenuItem(
                    title: item.project.title ?? item.id,
                    action: #selector(applyWallpaper(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = i
                mi.state = selected ? .on : .off
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())

        let muted = defaults.object(forKey: Prefs.muted) as? Bool ?? true
        let mute = NSMenuItem(title: "Muted",
                              action: #selector(toggleMute(_:)), keyEquivalent: "m")
        mute.target = self
        mute.state = muted ? .on : .off
        menu.addItem(mute)

        let stop = NSMenuItem(title: "Stop Wallpaper",
                              action: director.selectedItem != nil
                                  ? #selector(stopWallpaper(_:)) : nil, keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func chooseLibrary(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use Folder"
        panel.message = "Pick the folder that contains wallpaper folders (project.json inside)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaults.set(url.path, forKey: Prefs.libraryPath)
        loadLibrary()
    }

    @objc private func applyWallpaper(_ sender: NSMenuItem) {
        let videoItems = items.filter { $0.project.type == "video" }
        guard videoItems.indices.contains(sender.tag) else { return }
        let item = videoItems[sender.tag]
        do {
            try director.apply(item: item)
            defaults.set(item.id, forKey: Prefs.lastWallpaperID)
        } catch let err as UnsupportedWallpaperError {
            showError(err.description)
        } catch {
            showError("failed to apply '\(item.project.title ?? item.id)': \(error)")
        }
    }

    @objc private func toggleMute(_ sender: NSMenuItem) {
        let nowMuted = !(defaults.object(forKey: Prefs.muted) as? Bool ?? true)
        defaults.set(nowMuted, forKey: Prefs.muted)
        director.setMuted(nowMuted)
    }

    @objc private func stopWallpaper(_ sender: Any) {
        director.stopAll()
        defaults.removeObject(forKey: Prefs.lastWallpaperID)
    }

    // MARK: - Library loading

    private func loadLibrary() {
        items = []
        guard let path = defaults.string(forKey: Prefs.libraryPath) else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            defaults.removeObject(forKey: Prefs.libraryPath)
            return
        }
        items = (try? library.scan(folder: URL(fileURLWithPath: path))) ?? []

        // Auto-resume the last wallpaper on launch.
        if let lastID = defaults.string(forKey: Prefs.lastWallpaperID),
           let item = items.first(where: { $0.id == lastID }),
           director.selectedItem == nil {
            try? director.apply(item: item)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Wallpaper Engine"
        alert.informativeText = message
        alert.runModal()
    }

    private func lastPathComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
