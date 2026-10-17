import AppKit
import GlasspadKit

/// Dock mode: the Mac's Dock apps (com.apple.dock `persistent-apps`), then other running regular
/// apps, then recently used ones. Icons are rendered at `DockApp.iconPixels` (384 px, 3x the
/// largest tile the phone draws), cached on disk by bundle id + app modification date, and sent
/// to the phone once: the phone lists the icon keys it already has (`dockSync`).
@MainActor
public final class DockMode {
    public struct Entry: Equatable, Sendable {
        public var bundleID: String
        public var name: String
        public var url: URL?
        public init(bundleID: String, name: String, url: URL?) {
            self.bundleID = bundleID; self.name = name; self.url = url
        }
    }

    public struct RunningApp: Equatable, Sendable {
        public var bundleID: String
        public var name: String
        public var url: URL?
        public var active: Bool
        public var hidden: Bool
        public var pid: pid_t
        public init(bundleID: String, name: String, url: URL?, active: Bool, hidden: Bool = false, pid: pid_t = 0) {
            self.bundleID = bundleID; self.name = name; self.url = url; self.active = active
            self.hidden = hidden; self.pid = pid
        }
    }

    public struct Item: Equatable, Sendable {
        public var entry: Entry
        public var running: Bool
        public var active: Bool
        public var hidden: Bool
        public var inDock: Bool
        public var recent: Bool
    }

    public nonisolated static let iconPixels = DockApp.iconPixels
    /// Most recent apps listed after the Dock and running apps.
    public nonisolated static let recentLimit = 8

    public let workspace: DockWorkspace
    public let launcher: AppLauncher
    /// Icons read or drawn this session, oldest first, at most `memoryIconLimit` of them. The
    /// disk cache holds every one, so this only spares a read; it empties when the phone leaves.
    /// `iconCacheOrder` lists the keys oldest first.
    private var iconCache: [String: Data] = [:]
    private var iconCacheOrder: [String] = []
    /// About 2 MB of 384 px icons: a full Dock plus a search or two.
    public nonisolated static let memoryIconLimit = 48
    /// Icon keys the phone has: what it listed in `dockSync`, plus what this session sent.
    private var phoneIconKeys: Set<String> = []
    private let cacheDirectory: URL?
    /// Apps activated since launch, most recent first (fills "Recent" next to the Dock's own list).
    private var recentlyActivated: [Entry] = []

    public init(workspace: DockWorkspace = LiveDockWorkspace(),
                cacheDirectory: URL? = DockMode.defaultCacheDirectory()) {
        self.workspace = workspace
        self.launcher = AppLauncher(workspace: workspace)
        self.cacheDirectory = cacheDirectory
    }

    public nonisolated static func defaultCacheDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.soham109.glasspad", isDirectory: true) else { return nil }
        // Icons drawn at an older size (or by the first version, in "icons") are never used again.
        let stale = ["icons"] + [64, 256].filter { $0 != DockApp.iconPixels }.map { "icons-\($0)" }
        for name in stale {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(name))
        }
        return base.appendingPathComponent("icons-\(DockApp.iconPixels)", isDirectory: true)
    }

    /// Forget which icons the phone has (new session), and the icons kept in memory for it
    /// when they are on disk too.
    public func resetSession() {
        phoneIconKeys.removeAll()
        guard cacheDirectory != nil else { return }
        iconCache.removeAll()
        iconCacheOrder.removeAll()
    }

    /// Icons held in memory now (tests).
    var memoryIconCount: Int { iconCache.count }

    /// The phone listed the icons it already has.
    public func phoneHas(iconKeys: [String]) { phoneIconKeys.formUnion(iconKeys) }

    /// Records an app coming to the front, for the Recent list.
    public func noteActivated(_ entry: Entry) {
        recentlyActivated.removeAll { $0.bundleID == entry.bundleID }
        recentlyActivated.insert(entry, at: 0)
        if recentlyActivated.count > 20 { recentlyActivated.removeLast() }
    }

    // MARK: Pure parts (tested)

    /// Parses the `persistent-apps` (or `recent-apps`) array of com.apple.dock.
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

    /// Dock entries in Dock order, then running apps that are not in the Dock, then recent apps
    /// that are neither (at most `recentLimit`).
    public nonisolated static func merge(dock: [Entry], running: [RunningApp], recent: [Entry] = []) -> [Item] {
        let byID = Dictionary(running.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        var out = dock.map { e in
            Item(entry: e, running: byID[e.bundleID] != nil, active: byID[e.bundleID]?.active ?? false,
                 hidden: byID[e.bundleID]?.hidden ?? false, inDock: true, recent: false)
        }
        var seen = Set(dock.map(\.bundleID))
        for r in running where !seen.contains(r.bundleID) {
            seen.insert(r.bundleID)
            out.append(Item(entry: Entry(bundleID: r.bundleID, name: r.name, url: r.url), running: true,
                            active: r.active, hidden: r.hidden, inDock: false, recent: false))
        }
        var added = 0
        for e in recent where !seen.contains(e.bundleID) && added < recentLimit {
            seen.insert(e.bundleID)
            added += 1
            out.append(Item(entry: e, running: false, active: false, hidden: false, inDock: false, recent: true))
        }
        return out
    }

    /// `bundleID@seconds-pixels`: changes when the app is updated (or icons are drawn at a new
    /// size), so the phone fetches the new icon then.
    public nonisolated static func iconKey(bundleID: String, modified: Date?) -> String {
        "\(bundleID)@\(Int((modified ?? .distantPast).timeIntervalSince1970))-\(DockApp.iconPixels)"
    }

    /// Icon bytes per message. A full Dock of sharp icons is a few megabytes; in pieces of
    /// this size the list arrives at once and the icons right after, without one huge message.
    public nonisolated static let iconBudget = 1_500_000

    /// The list with icons kept up to `budget` bytes, and the apps whose icons move to
    /// follow-up `dockIcons` messages.
    public nonisolated static func splitIcons(_ apps: [DockApp], budget: Int = iconBudget) -> (list: [DockApp], later: [DockApp]) {
        var used = 0
        var later: [DockApp] = []
        let list = apps.map { app -> DockApp in
            guard let png = app.iconPNG else { return app }
            if used + png.count <= budget || used == 0 {
                used += png.count
                return app
            }
            later.append(app)
            var a = app
            a.iconPNG = nil
            return a
        }
        return (list, later)
    }

    /// Apps with icons in groups of at most `budget` bytes (one icon per group at least).
    public nonisolated static func iconBatches(_ apps: [DockApp], budget: Int = iconBudget) -> [[DockApp]] {
        var batches: [[DockApp]] = []
        var current: [DockApp] = [], used = 0
        for app in apps where app.iconPNG != nil {
            let size = app.iconPNG?.count ?? 0
            if !current.isEmpty, used + size > budget {
                batches.append(current)
                current = []
                used = 0
            }
            current.append(app)
            used += size
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    // MARK: Lists

    public func currentItems() -> [Item] {
        let prefs = workspace.dockPreferences()
        let dock = Self.parsePersistentApps(prefs.persistent)
        let recent = recentlyActivated + Self.parsePersistentApps(prefs.recent)
        return Self.merge(dock: dock, running: workspace.runningApps(), recent: recent)
    }

    public func currentList() -> [DockApp] {
        currentItems().map { item in
            let url = resolvedURL(item.entry)
            let key = Self.iconKey(bundleID: item.entry.bundleID, modified: url.flatMap(workspace.modificationDate))
            return DockApp(bundleID: item.entry.bundleID, name: item.entry.name, iconPNG: iconForPhone(key: key, url: url),
                           running: item.running, active: item.active, iconKey: key,
                           inDock: item.inDock, recent: item.recent, hidden: item.hidden)
        }
    }

    /// Every installed app by name, no icons.
    public func catalog() -> [DockApp] {
        var seen = Set<String>()
        return workspace.installedApps()
            .compactMap { app -> DockApp? in
                guard seen.insert(app.bundleID).inserted else { return nil }
                let key = Self.iconKey(bundleID: app.bundleID, modified: app.url.flatMap(workspace.modificationDate))
                return DockApp(bundleID: app.bundleID, name: app.name, running: false, active: false, iconKey: key)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Icons for apps the phone asked about (search results, Deck buttons).
    public func icons(for bundleIDs: [String]) -> [DockApp] {
        bundleIDs.prefix(60).compactMap { id in
            guard let url = workspace.applicationURLs(bundleID: id).first else { return nil }
            let key = Self.iconKey(bundleID: id, modified: workspace.modificationDate(url))
            guard let png = iconForPhone(key: key, url: url) else { return nil }
            return DockApp(bundleID: id, name: workspace.displayName(url) ?? id, iconPNG: png,
                           running: false, active: false, iconKey: key)
        }
    }

    private func resolvedURL(_ entry: Entry) -> URL? {
        if let url = entry.url, workspace.fileExists(url) { return url }
        return workspace.applicationURLs(bundleID: entry.bundleID).first
    }

    private func iconForPhone(key: String, url: URL?) -> Data? {
        guard !phoneIconKeys.contains(key), let url else { return nil }
        guard let png = iconPNG(key: key, url: url) else { return nil }
        phoneIconKeys.insert(key)
        return png
    }

    // MARK: Actions

    public func open(bundleID: String, completion: @escaping @MainActor (AppLauncher.Outcome) -> Void = { _ in }) {
        let dockURL = currentItems().first { $0.entry.bundleID == bundleID }?.entry.url
        launcher.open(bundleID: bundleID, preferredURL: dockURL, completion: completion)
    }

    /// Quit, hide, show or reveal. Returns false when the app is not running (or not found).
    @discardableResult
    public func perform(_ action: DockAppAction, bundleID: String) -> Bool {
        let app = workspace.runningApps().first { $0.bundleID == bundleID }
        GPLog.log("dock: \(action.rawValue) \(bundleID) running=\(app != nil)")
        switch action {
        case .quit: return app.map { workspace.terminate(pid: $0.pid) } ?? false
        case .hide: return app.map { workspace.hide(pid: $0.pid) } ?? false
        case .unhide: return app.map { workspace.unhide(pid: $0.pid) } ?? false
        case .revealInFinder:
            guard let url = app?.url ?? workspace.applicationURLs(bundleID: bundleID).first else { return false }
            workspace.reveal(url)
            return true
        }
    }

    // MARK: Icons

    func iconPNG(key: String, url: URL) -> Data? {
        if let d = iconCache[key] { return d }
        let file = cacheDirectory?.appendingPathComponent(Self.iconFileName(key))
        if let file, let d = try? Data(contentsOf: file) {
            remember(d, for: key)
            return d
        }
        guard let png = workspace.iconPNG(for: url, pixels: Self.iconPixels) else { return nil }
        remember(png, for: key)
        if let dir = cacheDirectory, let file {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? png.write(to: file, options: .atomic)
            Self.removeOlderIcons(of: key, in: dir)
        }
        return png
    }

    private func remember(_ png: Data, for key: String) {
        iconCache[key] = png
        iconCacheOrder.append(key)
        while iconCacheOrder.count > Self.memoryIconLimit {
            iconCache[iconCacheOrder.removeFirst()] = nil
        }
    }

    nonisolated static func iconFileName(_ key: String) -> String { key.replacingOccurrences(of: "/", with: "_") + ".png" }

    /// An app that updated gets a new key (its modification date is in it); the icon drawn for
    /// the old version is never read again, so it goes.
    nonisolated static func removeOlderIcons(of key: String, in dir: URL) {
        guard let at = key.lastIndex(of: "@") else { return }
        let prefix = iconFileName(String(key[..<at])).dropLast(4) + "@"
        let keep = iconFileName(key)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name != keep && name.hasPrefix(prefix) {
            // Only "<bundle id>@<date>-<size>.png": another app whose id starts the same way
            // ("com.a" and "com.a.helper") never matches, since "@" follows the whole id.
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Renders an image into an exact pixel-size bitmap and encodes it as PNG. Picks the image's
    /// best representation for that pixel size, so a 1024 px app icon is scaled down, never a
    /// small one scaled up.
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
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        if let best = image.bestRepresentation(for: rect, context: ctx, hints: [.interpolation: NSImageInterpolation.high.rawValue]) {
            best.draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        } else {
            image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        }
        ctx.flushGraphics()
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - Launching

/// Opens an app the way clicking it in the Mac's Dock does, with a log line for every step.
///
/// Why this exists (the "Word does not open" report): the first version called
/// `NSWorkspace.openApplication` with no completion handler and nothing else. For an app that
/// is already running, that is only an activation request. Glasspad is a background menu bar
/// app, and since macOS 14 activation is cooperative: a request from an app the user is not
/// using, triggered by a network message rather than a click on this Mac, may simply be ignored.
/// Microsoft Word keeps running after its last document closes (on the owner's Mac it had been
/// running for 22 days with no window on screen), so tapping it did nothing visible, and any
/// error was thrown away. Now a running app is unhidden, activated with all its windows, sent a
/// reopen event (which makes Word show its document gallery when it has no window), and if it
/// still is not frontmost half a second later it is brought forward through the window server.
/// An app that is not running is launched from the first location that exists: the Dock's own
/// URL, then every copy LaunchServices knows, then the usual app folders.
@MainActor
public final class AppLauncher {
    public enum Outcome: Equatable, Sendable {
        case activated(URL?)
        case launched(URL)
        case failed(String)

        public var ok: Bool { if case .failed = self { false } else { true } }
        public var message: String? { if case .failed(let m) = self { m } else { nil } }
    }

    private let workspace: DockWorkspace
    /// How long to wait before checking that a running app really came forward.
    public var settleDelay: TimeInterval = 0.5

    public init(workspace: DockWorkspace) { self.workspace = workspace }

    public func open(bundleID: String, preferredURL: URL? = nil,
                     completion: @escaping @MainActor (Outcome) -> Void) {
        if let app = workspace.runningApps().first(where: { $0.bundleID == bundleID }) {
            activate(app, completion: completion)
            return
        }
        let candidates = candidateURLs(bundleID: bundleID, preferredURL: preferredURL)
        GPLog.log("dock open \(bundleID): not running, candidates \(candidates.map(\.path))")
        guard !candidates.isEmpty else {
            GPLog.log("dock open \(bundleID): no app found")
            completion(.failed("This app is not installed on your Mac."))
            return
        }
        launch(bundleID: bundleID, candidates: candidates, lastError: nil, completion: completion)
    }

    /// Where the app could be, best first, without duplicates or missing paths.
    public func candidateURLs(bundleID: String, preferredURL: URL?) -> [URL] {
        var out: [URL] = []
        func add(_ url: URL?) {
            guard let url = url?.standardizedFileURL, workspace.fileExists(url),
                  !out.contains(where: { $0.path == url.path }) else { return }
            // A Dock tile can point at an old copy with another bundle id; skip those.
            if let id = workspace.bundleIdentifier(at: url), id != bundleID { return }
            out.append(url)
        }
        add(preferredURL)
        workspace.applicationURLs(bundleID: bundleID).forEach(add)
        workspace.installedApps().filter { $0.bundleID == bundleID }.forEach { add($0.url) }
        return out
    }

    private func launch(bundleID: String, candidates: [URL], lastError: String?,
                        completion: @escaping @MainActor (Outcome) -> Void) {
        guard let url = candidates.first else {
            completion(.failed(lastError ?? "Your Mac could not open this app."))
            return
        }
        GPLog.log("dock open \(bundleID): launching \(url.path)")
        workspace.launch(url, reopen: false) { [weak self] error in
            guard let self else { return }
            if let error {
                GPLog.log("dock open \(bundleID): launch failed at \(url.path): \(error)")
                self.launch(bundleID: bundleID, candidates: Array(candidates.dropFirst()), lastError: error, completion: completion)
            } else {
                GPLog.log("dock open \(bundleID): launched")
                completion(.launched(url))
            }
        }
    }

    private func activate(_ app: DockMode.RunningApp, completion: @escaping @MainActor (Outcome) -> Void) {
        GPLog.log("dock open \(app.bundleID): running pid \(app.pid), hidden=\(app.hidden), front=\(workspace.frontmostBundleID() ?? "-")")
        if app.hidden { _ = workspace.unhide(pid: app.pid) }
        let asked = workspace.activate(pid: app.pid)
        GPLog.log("dock open \(app.bundleID): activate request accepted=\(asked)")
        // Same as a Dock click: a reopen event makes an app with no open window show one.
        if let url = app.url {
            workspace.launch(url, reopen: true) { error in
                if let error { GPLog.log("dock open \(app.bundleID): reopen failed: \(error)") }
            }
        }
        workspace.after(settleDelay) { [weak self] in
            guard let self else { return }
            let front = self.workspace.frontmostBundleID()
            if front == app.bundleID {
                GPLog.log("dock open \(app.bundleID): frontmost")
            } else {
                let forced = self.workspace.bringToFront(pid: app.pid)
                GPLog.log("dock open \(app.bundleID): still behind \(front ?? "-"), window server front=\(forced)")
            }
            completion(.activated(app.url))
        }
    }
}

// MARK: - Workspace

/// Everything Dock mode asks of the Mac, so tests can run without opening or quitting apps.
@MainActor
public protocol DockWorkspace: AnyObject {
    /// com.apple.dock `persistent-apps` and `recent-apps`.
    func dockPreferences() -> (persistent: Any?, recent: Any?)
    /// Regular (Dock-showing) running apps.
    func runningApps() -> [DockMode.RunningApp]
    func frontmostBundleID() -> String?
    /// Every copy LaunchServices knows, preferred first.
    func applicationURLs(bundleID: String) -> [URL]
    /// Apps in /Applications, ~/Applications, /System/Applications and their Utilities folders.
    func installedApps() -> [(bundleID: String, name: String, url: URL?)]
    func fileExists(_ url: URL) -> Bool
    func bundleIdentifier(at url: URL) -> String?
    func displayName(_ url: URL) -> String?
    func modificationDate(_ url: URL) -> Date?
    func iconPNG(for url: URL, pixels: Int) -> Data?
    /// Launch (or, with `reopen`, send a running app the reopen event a Dock click sends).
    /// The completion gets a readable error or nil.
    func launch(_ url: URL, reopen: Bool, completion: @escaping @MainActor (String?) -> Void)
    func activate(pid: pid_t) -> Bool
    /// Last resort when activation was refused: the window server's own "bring to front".
    func bringToFront(pid: pid_t) -> Bool
    func hide(pid: pid_t) -> Bool
    func unhide(pid: pid_t) -> Bool
    func terminate(pid: pid_t) -> Bool
    func reveal(_ url: URL)
    func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void)
}

/// The real Mac.
@MainActor
public final class LiveDockWorkspace: DockWorkspace {
    private let ws = NSWorkspace.shared
    public init() {}

    public func dockPreferences() -> (persistent: Any?, recent: Any?) {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue("persistent-apps" as CFString, domain),
                CFPreferencesCopyAppValue("recent-apps" as CFString, domain))
    }

    public func runningApps() -> [DockMode.RunningApp] {
        let front = ws.frontmostApplication?.bundleIdentifier
        return ws.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier else { return nil }
                return DockMode.RunningApp(bundleID: id, name: app.localizedName ?? id, url: app.bundleURL,
                                           active: id == front, hidden: app.isHidden, pid: app.processIdentifier)
            }
    }

    public func frontmostBundleID() -> String? { ws.frontmostApplication?.bundleIdentifier }

    public func applicationURLs(bundleID: String) -> [URL] {
        var out: [URL] = []
        if let url = ws.urlForApplication(withBundleIdentifier: bundleID) { out.append(url) }
        for url in ws.urlsForApplications(withBundleIdentifier: bundleID) where !out.contains(url) { out.append(url) }
        return out
    }

    public func installedApps() -> [(bundleID: String, name: String, url: URL?)] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", home.appendingPathComponent("Applications").path]
        var out: [(bundleID: String, name: String, url: URL?)] = []
        for folder in folders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                out.append((id, displayName(url) ?? String(name.dropLast(4)), url))
            }
        }
        return out
    }

    public func fileExists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    public func bundleIdentifier(at url: URL) -> String? { Bundle(url: url)?.bundleIdentifier }

    public func displayName(_ url: URL) -> String? {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    public func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    public func iconPNG(for url: URL, pixels: Int) -> Data? {
        DockMode.renderPNG(ws.icon(forFile: url.path), pixels: pixels)
    }

    public func launch(_ url: URL, reopen: Bool, completion: @escaping @MainActor (String?) -> Void) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.promptsUserIfNeeded = true
        if reopen {
            // kCoreEventClass 'aevt' / kAEReopenApplication 'rapp': what the Dock sends on a click.
            config.appleEvent = NSAppleEventDescriptor(eventClass: 0x6165_7674, eventID: 0x7261_7070,
                                                       targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                                                       transactionID: AETransactionID(kAnyTransactionID))
        }
        ws.openApplication(at: url, configuration: config) { _, error in
            let text = error.map { ($0 as NSError).localizedDescription + " (\(($0 as NSError).domain) \(($0 as NSError).code))" }
            Task { @MainActor in completion(text) }
        }
    }

    public func activate(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows]) ?? false
    }

    public func bringToFront(pid: pid_t) -> Bool { WindowServerFront.bring(pid: pid) }
    public func hide(pid: pid_t) -> Bool { NSRunningApplication(processIdentifier: pid)?.hide() ?? false }
    public func unhide(pid: pid_t) -> Bool { NSRunningApplication(processIdentifier: pid)?.unhide() ?? false }
    public func terminate(pid: pid_t) -> Bool { NSRunningApplication(processIdentifier: pid)?.terminate() ?? false }
    public func reveal(_ url: URL) { ws.activateFileViewerSelecting([url]) }

    public func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { block() } }
    }
}

/// SkyLight's `_SLPSSetFrontProcessWithOptions` (private, loaded with dlsym, the call window
/// switchers use). Only used after a public activation request was ignored; returns false when
/// the symbols are missing, and the public request stands.
enum WindowServerFront {
    private struct PSN { var high: UInt32 = 0; var low: UInt32 = 0 }
    private typealias GetPSN = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias SetFront = @convention(c) (UnsafeRawPointer, UInt32, UInt32) -> Int32
    /// kCPSUserGenerated: the request counts as if the user clicked.
    private static let userGenerated: UInt32 = 0x200

    static func bring(pid: pid_t) -> Bool {
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let setSym = dlsym(sky, "_SLPSSetFrontProcessWithOptions"),
              let psnSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID") else { return false }
        var psn = PSN()
        let got = withUnsafeMutableBytes(of: &psn) { unsafeBitCast(psnSym, to: GetPSN.self)(pid, $0.baseAddress!) }
        guard got == 0 else { return false }
        return withUnsafeBytes(of: &psn) { unsafeBitCast(setSym, to: SetFront.self)($0.baseAddress!, 0, userGenerated) } == 0
    }
}
