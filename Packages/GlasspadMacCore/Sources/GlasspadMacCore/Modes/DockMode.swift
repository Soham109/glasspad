import AppKit
import GlasspadKit

/// Dock mode: the Mac's Dock apps (com.apple.dock persistent-apps) followed by other running
/// regular apps, with 64 px PNG icons cached by bundle id.
@MainActor
public final class DockMode {
    public struct Entry: Equatable, Sendable {
        public var bundleID: String
        public var name: String
        public var url: URL?
    }

    public struct RunningApp: Equatable, Sendable {
        public var bundleID: String
        public var name: String
        public var url: URL?
        public var active: Bool
        public init(bundleID: String, name: String, url: URL?, active: Bool) {
            self.bundleID = bundleID; self.name = name; self.url = url; self.active = active
        }
    }

    public static let iconPixels = 64
    private var iconCache: [String: Data] = [:]
    /// Bundle ids whose icon this session's phone already has.
    private var sentIcons: Set<String> = []
    private let cacheDirectory: URL?

    public init(cacheDirectory: URL? = DockMode.defaultCacheDirectory()) {
        self.cacheDirectory = cacheDirectory
    }

    public nonisolated static func defaultCacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.soham109.glasspad/icons", isDirectory: true)
    }

    /// Forget which icons the phone has (new session).
    public func resetSession() { sentIcons.removeAll() }

    // MARK: Pure parts (tested)

    /// Parses the `persistent-apps` array of com.apple.dock.
    public nonisolated static func parsePersistentApps(_ value: Any?) -> [Entry] {
        guard let tiles = value as? [[String: Any]] else { return [] }
        return tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let bundleID = data["bundle-identifier"] as? String, !bundleID.isEmpty else { return nil }
            let name = data["file-label"] as? String ?? bundleID
            var url: URL?
            if let file = data["file-data"] as? [String: Any], let s = file["_CFURLString"] as? String {
                url = URL(string: s)
            }
            return Entry(bundleID: bundleID, name: name, url: url)
        }
    }

    /// Dock entries in Dock order, then running apps that are not in the Dock.
    public nonisolated static func merge(dock: [Entry], running: [RunningApp]) -> [(entry: Entry, running: Bool, active: Bool)] {
        let byID = Dictionary(running.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        var out = dock.map { e in (entry: e, running: byID[e.bundleID] != nil, active: byID[e.bundleID]?.active ?? false) }
        let inDock = Set(dock.map(\.bundleID))
        for r in running where !inDock.contains(r.bundleID) {
            out.append((Entry(bundleID: r.bundleID, name: r.name, url: r.url), true, r.active))
        }
        return out
    }

    // MARK: Live

    public func currentList() -> [DockApp] {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let dock = Self.parsePersistentApps(CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString))
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier else { return nil }
                return RunningApp(bundleID: id, name: app.localizedName ?? id, url: app.bundleURL, active: id == frontmost)
            }
        return Self.merge(dock: dock, running: running).map { item in
            let icon: Data?
            if sentIcons.contains(item.entry.bundleID) {
                icon = nil
            } else {
                icon = iconPNG(bundleID: item.entry.bundleID, url: item.entry.url)
                if icon != nil { sentIcons.insert(item.entry.bundleID) }
            }
            return DockApp(bundleID: item.entry.bundleID, name: item.entry.name, iconPNG: icon,
                           running: item.running, active: item.active)
        }
    }

    public func open(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
    }

    func iconPNG(bundleID: String, url: URL?) -> Data? {
        if let d = iconCache[bundleID] { return d }
        let file = cacheDirectory?.appendingPathComponent(bundleID + ".png")
        if let file, let d = try? Data(contentsOf: file) {
            iconCache[bundleID] = d
            return d
        }
        guard let appURL = url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        guard let png = Self.renderPNG(image, pixels: Self.iconPixels) else { return nil }
        iconCache[bundleID] = png
        if let dir = cacheDirectory, let file {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? png.write(to: file, options: .atomic)
        }
        return png
    }

    /// Renders an image into an exact pixel-size bitmap and encodes it as PNG.
    public nonisolated static func renderPNG(_ image: NSImage, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        ctx.flushGraphics()
        return rep.representation(using: .png, properties: [:])
    }
}
