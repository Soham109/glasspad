import AppKit
import GlasspadKit

/// Deck config, stored as JSON at ~/Library/Application Support/Glasspad/deck.json.
///
/// Version 1 had a flat `buttons` list; version 2 adds pages (with optional app links), folders
/// (buttons with children) and grid density. `buttons` is still written (every runnable button,
/// flattened) so an older phone keeps working.
///
/// Trust: the phone can edit the Deck (`deckSave`), but it can never add or change a shell
/// script button or turn shell buttons on. Those stay Mac-only.
public struct DeckConfig: Codable, Equatable, Sendable {
    public var version: Int
    /// Shell-script buttons run only when the user turned this on explicitly on the Mac.
    public var allowShellCommands: Bool
    public var buttons: [DeckButton]
    public var pages: [DeckPage]?
    public var columns: Int?

    /// Version 3 adds the built-in "Mac" page of system controls in front of the user's pages.
    public static let currentVersion = 3
    /// Fixed ids so the phone can recognise the two built-in pages.
    public static let macPageID = UUID(uuidString: "6D61632D-0000-4000-8000-000000000001")!
    public static let myPageID = UUID(uuidString: "6D61632D-0000-4000-8000-000000000002")!

    public init(version: Int = DeckConfig.currentVersion, allowShellCommands: Bool = false,
                buttons: [DeckButton] = [],
                pages: [DeckPage]? = DeckConfig.starterPages(), columns: Int? = nil) {
        self.version = version
        self.allowShellCommands = allowShellCommands
        self.buttons = buttons
        self.pages = pages
        self.columns = columns
    }

    public init(layout: DeckLayout, allowShellCommands: Bool) {
        self.init(version: Self.currentVersion, allowShellCommands: allowShellCommands,
                  buttons: layout.allButtons.filter { $0.action != .folder },
                  pages: layout.pages, columns: layout.columns)
    }

    /// Pages, made from the flat list for a version 1 file.
    public var layout: DeckLayout {
        DeckLayout(pages: pages ?? [DeckPage(title: "Main", symbol: "square.grid.2x2", buttons: buttons)],
                   columns: columns, allowsShellCommands: allowShellCommands)
    }

    /// The pages a new Deck starts with: only Pinned, holding six everyday Mac controls. The
    /// rest of the Mac controls are in the phone's Library, one tap away.
    public static func starterPages() -> [DeckPage] {
        [DeckPage(id: myPageID, title: "Pinned", symbol: "pin", buttons: PinnedDeck.essentials())]
    }

    public static let myStarterButtons: [DeckButton] = [
        DeckButton(title: "Safari", symbol: "safari", action: .openApp(bundleID: "com.apple.Safari"), color: "#0A84FF"),
        DeckButton(title: "Downloads", symbol: "arrow.down.circle.fill", action: .openFile(path: "~/Downloads"), color: "#34C759"),
    ]

    /// System controls, each made fresh (new ids) for a new config.
    public static func macStarterButtons() -> [DeckButton] {
        func b(_ t: String, _ s: String, _ a: DeckAction, _ c: String) -> DeckButton { DeckButton(title: t, symbol: s, action: a, color: c) }
        return [
            b("Screenshot", "camera.viewfinder", .screenshot(DeckScreenshot(area: .fullScreen)), "#0A84FF"),
            b("Window Shot", "macwindow", .screenshot(DeckScreenshot(area: .frontWindow)), "#0A84FF"),
            b("Area Shot", "rectangle.dashed", .screenshot(DeckScreenshot(area: .selection)), "#0A84FF"),
            b("Record", "record.circle", .screenRecording, "#FF453A"),
            b("Lock", "lock.fill", .system(.lockScreen), "#8E8E93"),
            b("Sleep Display", "moon.fill", .system(.sleepDisplay), "#5E5CE6"),
            b("Dark Mode", "circle.lefthalf.filled", .system(.toggleDarkMode), "#636366"),
            b("Focus", "moon.circle.fill", .runShortcut(name: "Toggle Focus"), "#5E5CE6"),
            b("Volume Down", "speaker.minus.fill", .system(.volumeDown), "#FF9F0A"),
            b("Volume Up", "speaker.plus.fill", .system(.volumeUp), "#FF9F0A"),
            b("Mute", "speaker.slash.fill", .system(.mute), "#FF9F0A"),
            b("Mic", "mic.slash.fill", .system(.micMute), "#FF375F"),
            b("Play / Pause", "playpause.fill", .system(.playPause), "#FF375F"),
            b("Desktop", "menubar.dock.rectangle", .system(.showDesktop), "#30B0C7"),
            b("Mission Control", "rectangle.3.group", .system(.missionControl), "#30B0C7"),
            b("Apps", "square.grid.3x3", .system(.launchpad), "#30B0C7"),
            b("Brightness Down", "sun.min.fill", .system(.brightnessDown), "#FFD60A"),
            b("Brightness Up", "sun.max.fill", .system(.brightnessUp), "#FFD60A"),
            b("Eject All", "eject.fill", .system(.ejectAll), "#8E8E93"),
            b("Empty Trash", "trash.fill", .system(.emptyTrash), "#8E8E93"),
        ]
    }

    /// Brings an older file up to date without losing anything: a version 1 flat list becomes
    /// the "My Buttons" page, and the Mac page is added in front once.
    public func migrated() -> DeckConfig {
        guard version < Self.currentVersion else { return self }
        var cfg = self
        var pages = self.pages ?? [DeckPage(id: Self.myPageID, title: "My Buttons", symbol: "star", buttons: buttons)]
        if !pages.contains(where: { $0.id == Self.macPageID }) {
            pages.insert(DeckPage(id: Self.macPageID, title: "Mac", symbol: "macbook", buttons: Self.macStarterButtons()), at: 0)
        }
        cfg.pages = pages
        cfg.version = Self.currentVersion
        cfg.buttons = DeckLayout(pages: pages).allButtons.filter { $0.action != .folder }
        return cfg
    }

    /// The version 2 starter list (kept for reference by older tests and configs).
    public static let starterButtons: [DeckButton] = [
        DeckButton(title: "Screenshot", symbol: "camera.viewfinder", action: .screenshot(DeckScreenshot(area: .fullScreen)),
                   color: "#0A84FF"),
        DeckButton(title: "Window Shot", symbol: "macwindow", action: .screenshot(DeckScreenshot(area: .frontWindow)),
                   color: "#5E5CE6"),
        DeckButton(title: "Lock", symbol: "lock.fill", action: .system(.lockScreen), color: "#8E8E93"),
        DeckButton(title: "Play / Pause", symbol: "playpause.fill", action: .system(.playPause), color: "#FF375F"),
        DeckButton(title: "Volume Down", symbol: "speaker.minus.fill", action: .system(.volumeDown), color: "#FF9F0A"),
        DeckButton(title: "Volume Up", symbol: "speaker.plus.fill", action: .system(.volumeUp), color: "#FF9F0A"),
        DeckButton(title: "Mission Control", symbol: "rectangle.3.group", action: .system(.missionControl), color: "#30B0C7"),
        DeckButton(title: "Desktop", symbol: "menubar.dock.rectangle", action: .system(.showDesktop), color: "#30B0C7"),
        DeckButton(title: "Dark Mode", symbol: "circle.lefthalf.filled", action: .system(.toggleDarkMode), color: "#636366"),
        DeckButton(title: "Safari", symbol: "safari", action: .openApp(bundleID: "com.apple.Safari"), color: "#0A84FF"),
        DeckButton(title: "Downloads", symbol: "arrow.down.circle.fill", action: .openFile(path: "~/Downloads"), color: "#34C759"),
        DeckButton(title: "Sleep Display", symbol: "moon.fill", action: .system(.sleepDisplay), color: "#5E5CE6"),
    ]

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Glasspad/deck.json")
    }

    public static func load(from url: URL = defaultURL()) -> DeckConfig {
        guard let data = try? Data(contentsOf: url), let cfg = try? JSONDecoder().decode(DeckConfig.self, from: data) else {
            return DeckConfig()
        }
        return cfg.migrated()
    }

    public func save(to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    /// Checks a layout the phone sent. Shell buttons are kept only when the same button (same
    /// id, same script) is already in this config; anything else is refused.
    public func validatedPhoneEdit(_ layout: DeckLayout) -> Result<DeckConfig, DeckEditError> {
        let existing = Dictionary(self.layout.allButtons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for button in layout.allButtons {
            if case .shellScript = button.action, existing[button.id]?.action != button.action {
                return .failure(.shellFromPhone)
            }
            if button.action == .folder, (button.children ?? []).flattenedDeck.count > 200 {
                return .failure(.tooLarge)
            }
        }
        guard layout.pages.count <= 30, layout.allButtons.count <= 600 else { return .failure(.tooLarge) }
        var clean = layout
        if let c = clean.columns { clean.columns = min(6, max(2, c)) }
        if clean.pages.isEmpty { clean.pages = [DeckPage(title: "Main", buttons: [])] }
        clean.allowsShellCommands = nil
        return .success(DeckConfig(layout: clean, allowShellCommands: allowShellCommands))
    }
}

public enum DeckEditError: Error, Equatable, Sendable {
    case shellFromPhone, tooLarge

    public var message: String {
        switch self {
        case .shellFromPhone: "Shell script buttons can only be added on the Mac."
        case .tooLarge: "That Deck is too large."
        }
    }
}

// MARK: - Environment

/// A long-running tool started by a button (a screen recording).
@MainActor
public protocol DeckProcess: AnyObject {
    var isRunning: Bool { get }
    /// Ask it to finish and save (SIGINT, like pressing ctrl+C).
    func interrupt()
}

/// Side effects of Deck actions, injectable so tests never launch, capture or change anything.
@MainActor
public protocol DeckEnvironment: AnyObject {
    func openApp(bundleID: String) async -> Bool
    func open(url: URL) -> Bool
    func fileExists(_ url: URL) -> Bool
    var homeDirectory: URL { get }
    func run(executable: String, arguments: [String], timeout: TimeInterval) async -> (ok: Bool, output: String)
    func start(executable: String, arguments: [String]) -> DeckProcess?
    func press(_ keystroke: Keystroke)
    func type(_ text: String)
    func runMacro(_ id: UUID) async -> (ok: Bool, message: String?)
    func media(_ command: MediaCommand)
    var outputVolume: Double? { get }
    func setOutputVolume(_ value: Double)
    func toggleOutputMute() -> Bool
    var inputMuted: Bool? { get }
    func setInputMuted(_ muted: Bool) -> Bool
    var brightness: Double? { get }
    func setBrightness(_ value: Double)
    func audioOutputs() -> [String]
    func setAudioOutput(name: String) -> Bool
    /// Ejects every ejectable volume; returns how many went and how many refused.
    func ejectAll() -> (ejected: Int, failed: Int)
    /// com.apple.screencapture `location`, else the Desktop.
    func screenshotFolder() -> URL
    /// Window id of the frontmost app's front window.
    func frontWindowID() -> UInt32?
    func now() -> Date
    /// The image file, ready to send to the phone (re-encoded if very large).
    func phoneImageData(_ url: URL) -> Data?
    func copyImageToClipboard(_ url: URL) -> Bool
    func shortcutNames() async -> [String]
}

extension DeckEnvironment {
    public func run(executable: String, arguments: [String]) async -> (ok: Bool, output: String) {
        await run(executable: executable, arguments: arguments, timeout: 15)
    }
}

// MARK: - Deck

@MainActor
public final class DeckMode {
    public private(set) var config: DeckConfig
    private let env: DeckEnvironment
    private let url: URL
    private var recording: DeckProcess?

    /// Volume and brightness step for the up/down buttons: one of the Mac's 16 keyboard steps.
    public static let step = 1.0 / 16

    public static let missionControlPath = "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control"
    public static let osascript = "/usr/bin/osascript"
    public static let automationHint = "Allow Glasspad in System Settings > Privacy & Security > Automation."

    public init(env: DeckEnvironment, url: URL = DeckConfig.defaultURL()) {
        self.env = env
        self.url = url
        self.config = DeckConfig.load(from: url)
        reload()
    }

    /// Reads the file. A missing or older file is written back, so button ids stay the same
    /// between requests (the phone runs buttons by id).
    public func reload() {
        let onDisk = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(DeckConfig.self, from: $0) }
        config = DeckConfig.load(from: url)
        if onDisk == nil || onDisk?.version != config.version { try? config.save(to: url) }
    }

    public func update(_ cfg: DeckConfig) throws {
        try cfg.save(to: url)
        config = cfg
    }

    /// The phone's edited Deck.
    public func savePhoneEdit(_ layout: DeckLayout) -> ModeMessage {
        reload()
        switch config.validatedPhoneEdit(layout) {
        case .failure(let e):
            return .deckSaveResult(ok: false, message: e.message)
        case .success(let cfg):
            do {
                try update(cfg)
                return .deckSaveResult(ok: true, message: nil)
            } catch {
                return .deckSaveResult(ok: false, message: "Could not save the Deck on the Mac.")
            }
        }
    }

    public func catalog() async -> DeckCatalog {
        DeckCatalog(audioOutputs: env.audioOutputs(), shortcuts: await env.shortcutNames())
    }

    /// Runs the button and returns what to send the phone: the result, and an image if the
    /// button made one for it.
    public func run(id: UUID, confirmed: Bool = false) async -> [ModeMessage] {
        guard let button = config.layout.button(id: id) else {
            return [.deckResult(id: id, ok: false, message: "Button not found")]
        }
        if button.needsConfirmation && !confirmed {
            return [.deckResult(id: id, ok: false, message: "Confirm on the phone first.")]
        }
        GPLog.log("deck: run \(button.title) \(Self.logLabel(button.action))")
        let outcome = await perform(button.action)
        var out: [ModeMessage] = [.deckResult(id: id, ok: outcome.ok, message: outcome.ok ? nil : outcome.message)]
        if let image = outcome.image { out.append(.deckImage(id: id, imageData: image.data, destination: image.destination)) }
        return out
    }

    /// The action for the log, without typed text or a script: the log is public and kept.
    nonisolated static func logLabel(_ action: DeckAction) -> String {
        switch action {
        case .typeText: "typeText"
        case .shellScript: "shellScript"
        default: "\(action)"
        }
    }

    public struct Outcome: Equatable, Sendable {
        public var ok: Bool
        public var message: String?
        public var image: (data: Data, destination: DeckImageDestination)?

        static let done = Outcome(ok: true)
        static func fail(_ m: String) -> Outcome { Outcome(ok: false, message: m) }

        public init(ok: Bool, message: String? = nil, image: (data: Data, destination: DeckImageDestination)? = nil) {
            self.ok = ok; self.message = message; self.image = image
        }

        public static func == (a: Outcome, b: Outcome) -> Bool {
            a.ok == b.ok && a.message == b.message && a.image?.data == b.image?.data && a.image?.destination == b.image?.destination
        }
    }

    public func perform(_ action: DeckAction) async -> Outcome {
        switch action {
        case .openApp(let bundleID):
            return await env.openApp(bundleID: bundleID) ? .done : .fail("App not found")
        case .openURL(let s):
            guard let u = URL(string: s), u.scheme != nil, u.scheme?.lowercased() != "file" else { return .fail("Invalid URL") }
            return env.open(url: u) ? .done : .fail("Could not open URL")
        case .openFile(let path):
            guard let file = resolve(path) else { return .fail("Use a full path, like ~/Documents") }
            guard env.fileExists(file) else { return .fail("\(file.lastPathComponent) is not on this Mac") }
            return env.open(url: file) ? .done : .fail("Could not open \(file.lastPathComponent)")
        case .runShortcut(let name):
            let r = await env.run(executable: "/usr/bin/shortcuts", arguments: ["run", name], timeout: 60)
            return r.ok ? .done : .fail("Shortcut \u{201C}\(name)\u{201D} failed")
        case .runMacro(let id):
            let r = await env.runMacro(id)
            return r.ok ? .done : .fail(r.message ?? "Macro failed")
        case .keystroke(let k):
            env.press(k)
            return .done
        case .typeText(let text):
            env.type(text)
            return .done
        case .shellScript(let script):
            guard config.allowShellCommands else { return .fail("Shell commands are turned off on the Mac") }
            let r = await env.run(executable: "/bin/zsh", arguments: ["-c", script], timeout: 30)
            return r.ok ? .done : .fail(String(r.output.suffix(200)))
        case .screenshot(let shot):
            return await screenshot(shot)
        case .screenRecording:
            return toggleRecording()
        case .system(let s):
            return await system(s)
        case .setAudioOutput(let name):
            return env.setAudioOutput(name: name) ? .done : .fail("No sound output named \(name)")
        case .folder:
            return .fail("Folders open on the phone")
        }
    }

    // MARK: Files and names

    func resolve(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed == "~" { return env.homeDirectory }
        if trimmed.hasPrefix("~/") { return env.homeDirectory.appendingPathComponent(String(trimmed.dropFirst(2))) }
        guard trimmed.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: trimmed)
    }

    /// "Screenshot 2026-10-15 at 16.05.12.png", the name macOS itself uses.
    public static func fileName(_ prefix: String, date: Date, ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(f.string(from: date)).\(ext)"
    }

    // MARK: Screenshots and recording

    /// `screencapture` arguments for a capture into `file`, or nil when there is no front window.
    public func screencaptureArguments(_ area: DeckCaptureArea, file: URL) -> [String]? {
        switch area {
        case .fullScreen: return [file.path]
        case .frontWindow:
            guard let wid = env.frontWindowID() else { return nil }
            return ["-l", String(wid), file.path]
        case .selection: return ["-i", "-s", file.path]
        }
    }

    private func screenshot(_ shot: DeckScreenshot) async -> Outcome {
        let file = env.screenshotFolder().appendingPathComponent(Self.fileName("Screenshot", date: env.now(), ext: "png"))
        guard let args = screencaptureArguments(shot.area, file: file) else { return .fail("No window to capture") }
        // A selection waits for you to drag on the Mac (with the phone as the trackpad).
        let r = await env.run(executable: "/usr/sbin/screencapture", arguments: args,
                              timeout: shot.area == .selection ? 120 : 20)
        guard env.fileExists(file) else {
            if shot.area == .selection, r.ok { return .fail("Screenshot cancelled") }
            return .fail("Allow Glasspad in System Settings > Privacy & Security > Screen & System Audio Recording.")
        }
        if shot.copyToMacClipboard == true { _ = env.copyImageToClipboard(file) }
        var outcome = Outcome.done
        if let destination = shot.sendToPhone {
            guard let data = env.phoneImageData(file) else { return .fail("Saved on the Mac, but too large to send") }
            outcome.image = (data, destination)
        }
        return outcome
    }

    public var isRecording: Bool { recording?.isRunning == true }

    private func toggleRecording() -> Outcome {
        if let rec = recording, rec.isRunning {
            rec.interrupt()
            recording = nil
            return .done
        }
        let file = env.screenshotFolder().appendingPathComponent(Self.fileName("Screen Recording", date: env.now(), ext: "mov"))
        guard let p = env.start(executable: "/usr/sbin/screencapture", arguments: ["-v", "-k", file.path]) else {
            return .fail("Could not start recording")
        }
        recording = p
        return .done
    }

    // MARK: System controls

    private func system(_ s: DeckSystemAction) async -> Outcome {
        switch s {
        case .lockScreen:
            env.press(Keystroke(key: .character("q"), modifiers: [.command, .control]))
            return .done
        case .sleepDisplay:
            return await tool("/usr/bin/pmset", ["displaysleepnow"], "Could not sleep the display")
        case .sleepMac:
            return await tool("/usr/bin/pmset", ["sleepnow"], "Could not sleep the Mac")
        case .toggleDarkMode:
            return await tool(Self.osascript, ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"],
                              Self.automationHint)
        case .volumeUp, .volumeDown:
            guard let v = env.outputVolume else { return .fail("This sound output has no volume control") }
            env.setOutputVolume(min(1, max(0, v + (s == .volumeUp ? Self.step : -Self.step))))
            return .done
        case .mute:
            return env.toggleOutputMute() ? .done : .fail("This sound output cannot be muted")
        case .micMute:
            guard let muted = env.inputMuted else { return .fail("No microphone found") }
            return env.setInputMuted(!muted) ? .done : .fail("This microphone cannot be muted")
        case .brightnessUp, .brightnessDown:
            guard let b = env.brightness else { return .fail("This display's brightness cannot be changed from Glasspad") }
            env.setBrightness(min(1, max(0, b + (s == .brightnessUp ? Self.step : -Self.step))))
            return .done
        case .playPause: env.media(.playPause); return .done
        case .nextTrack: env.media(.nextTrack); return .done
        case .previousTrack: env.media(.previousTrack); return .done
        case .showDesktop: return await tool(Self.missionControlPath, ["1"], "Could not show the desktop")
        case .missionControl: return await tool(Self.missionControlPath, [], "Could not open Mission Control")
        case .appExpose: return await tool(Self.missionControlPath, ["2"], "Could not show App Exposé")
        case .launchpad:
            if await env.openApp(bundleID: "com.apple.apps.launcher") { return .done }
            return await env.openApp(bundleID: "com.apple.launchpad.launcher") ? .done : .fail("Could not open Apps")
        case .emptyTrash:
            return await tool(Self.osascript, ["-e", "tell application \"Finder\" to empty trash"], Self.automationHint)
        case .ejectAll:
            let r = env.ejectAll()
            if r.failed > 0 { return .fail("\(r.failed) disk\(r.failed == 1 ? "" : "s") could not be ejected (in use)") }
            return .done
        default:
            return .fail("Not built yet")
        }
    }

    private func tool(_ path: String, _ args: [String], _ failure: String) async -> Outcome {
        let r = await env.run(executable: path, arguments: args, timeout: 15)
        return r.ok ? .done : .fail(failure)
    }
}
