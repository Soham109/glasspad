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

    enum CodingKeys: String, CodingKey { case version, allowShellCommands, buttons, pages, columns }

    /// One button this build cannot read costs that button, not the whole file (which would
    /// bring back the starter set).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        allowShellCommands = try c.decode(Bool.self, forKey: .allowShellCommands)
        buttons = try c.decode([LenientButton].self, forKey: .buttons).compactMap(\.value)
        pages = try c.decodeIfPresent([LenientPage].self, forKey: .pages)?.compactMap(\.value)
        columns = try c.decodeIfPresent(Int.self, forKey: .columns)
    }

    private struct LenientButton: Decodable {
        let value: DeckButton?
        init(from decoder: Decoder) throws { value = try? DeckButton(from: decoder) }
    }

    private struct LenientPage: Decodable {
        let value: DeckPage?
        init(from decoder: Decoder) throws { value = try? DeckPage(from: decoder) }
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
            b("Do Not Disturb", "moon.circle.fill", .system(.doNotDisturb), "#5E5CE6"),
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
        guard version < Self.currentVersion else { return replacingRetiredActions() }
        var cfg = replacingRetiredActions()
        var pages = self.pages ?? [DeckPage(id: Self.myPageID, title: "My Buttons", symbol: "star", buttons: buttons)]
        if !pages.contains(where: { $0.id == Self.macPageID }) {
            pages.insert(DeckPage(id: Self.macPageID, title: "Mac", symbol: "macbook", buttons: Self.macStarterButtons()), at: 0)
        }
        cfg.pages = pages
        cfg.version = Self.currentVersion
        cfg.buttons = DeckLayout(pages: pages).allButtons.filter { $0.action != .folder }
        return cfg
    }

    /// The old Mac page's Focus button ran a shortcut named "Toggle Focus" that nobody had, so
    /// it never worked. It becomes the built-in Do Not Disturb switch. Buttons the user pointed
    /// at a shortcut of their own are left alone.
    public static let retiredFocusShortcut = "Toggle Focus"

    func replacingRetiredActions() -> DeckConfig {
        func fix(_ b: DeckButton) -> DeckButton {
            var b = b
            if b.action == .runShortcut(name: Self.retiredFocusShortcut) {
                b.action = .system(.doNotDisturb)
                if b.title == "Focus" { b.title = "Do Not Disturb" }
            }
            b.children = b.children?.map(fix)
            return b
        }
        var cfg = self
        cfg.buttons = buttons.map(fix)
        cfg.pages = pages?.map { p in
            var p = p
            p.buttons = p.buttons.map(fix)
            return p
        }
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
            // An action newer than this Mac cannot be checked, so the phone may only keep one
            // that was already here (saved by a newer Mac), never add or change one.
            if !button.action.isSupported, existing[button.id]?.action != button.action {
                return .failure(.newerThanMac)
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
    case shellFromPhone, tooLarge, newerThanMac

    public var message: String {
        switch self {
        case .shellFromPhone: "Shell script buttons can only be added on the Mac."
        case .tooLarge: "That Deck is too large."
        case .newerThanMac: "This Deck has a button your Mac does not know yet. Update Glasspad on your Mac, then try again."
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
    /// True while the default output is muted; nil when it has no mute.
    var outputMuted: Bool? { get }
    /// How many displays are connected (one screenshot file each).
    var displayCount: Int { get }
    /// Locks the screen directly; false when that is not available (the caller then presses
    /// control command Q).
    func lockScreen() -> Bool
    /// Switches light and dark without the Automation prompt; the new state (true is dark), or
    /// nil when that did not work and AppleScript should do it.
    func toggleDarkMode() -> Bool?
    func toggleDoNotDisturb() async -> DeckSwitchResult
    func toggleNightShift() -> DeckSwitchResult
    func toggleKeepAwake() -> DeckSwitchResult
    func openNotificationCenter() -> Bool
    /// Moves the front window; nil when done, else why not.
    func placeFrontWindow(_ placement: WindowPlacement) -> String?
    /// The two front windows side by side; nil when done, else why not.
    func splitFrontWindows() -> String?
    /// The front window to the next display; nil when done, else why not.
    func moveFrontWindowToNextDisplay() -> String?
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
    /// How long a new recording must keep running to count as started (it quits at once when
    /// Screen Recording is not allowed). Tests set it to zero.
    var recordingStartCheck: Duration = .milliseconds(700)

    /// Volume and brightness step for the up/down buttons: one of the Mac's 16 keyboard steps.
    public static let step = 1.0 / 16

    public static let missionControlPath = "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control"
    public static let osascript = "/usr/bin/osascript"
    /// Running a button from a newer Glasspad.
    public static let updateToUse = "Update Glasspad on your Mac to use this button."
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
        if onDisk == nil || onDisk != config { try? config.save(to: url) }
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
        // On success the message is the new state of a switch ("Do Not Disturb is on"), if any.
        var out: [ModeMessage] = [.deckResult(id: id, ok: outcome.ok, message: outcome.message)]
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
            return await runShortcut(name)
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
            return await toggleRecording()
        case .system(let s):
            return await system(s)
        case .setAudioOutput(let name):
            return env.setAudioOutput(name: name) ? .done : .fail("No sound output named \u{201C}\(name)\u{201D} is connected")
        case .folder:
            return .fail("Folders open on the phone")
        case .unsupported:
            return .fail(Self.updateToUse)
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
    /// A full screen capture names one file per display, as macOS does ("... (2).png").
    public func screencaptureArguments(_ area: DeckCaptureArea, file: URL) -> [String]? {
        switch area {
        case .fullScreen:
            let count = max(1, env.displayCount)
            return [file.path] + (count > 1 ? (2...count).map { Self.numbered(file, $0).path } : [])
        case .frontWindow:
            guard let wid = env.frontWindowID() else { return nil }
            return ["-l", String(wid), file.path]
        // Interactive, mouse selection only: the crosshair, never the screenshot toolbar.
        case .selection: return ["-i", "-s", file.path]
        }
    }

    /// "Screenshot ... (2).png" for the second display.
    nonisolated static func numbered(_ file: URL, _ n: Int) -> URL {
        let base = file.deletingPathExtension().lastPathComponent
        return file.deletingLastPathComponent().appendingPathComponent("\(base) (\(n)).\(file.pathExtension)")
    }

    private func screenshot(_ shot: DeckScreenshot) async -> Outcome {
        let file = env.screenshotFolder().appendingPathComponent(Self.fileName("Screenshot", date: env.now(), ext: "png"))
        guard let args = screencaptureArguments(shot.area, file: file) else { return .fail("No window to capture") }
        // A selection waits for you to drag on the Mac (with the phone as the trackpad).
        let r = await env.run(executable: "/usr/sbin/screencapture", arguments: args,
                              timeout: shot.area == .selection ? 120 : 20)
        guard env.fileExists(file) else {
            if shot.area == .selection, r.ok { return .fail("Screenshot cancelled") }
            return .fail(Self.screenRecordingHint)
        }
        if shot.copyToMacClipboard == true { _ = env.copyImageToClipboard(file) }
        var outcome = Outcome.done
        if let destination = shot.sendToPhone {
            guard let data = env.phoneImageData(file) else { return .fail("Saved on the Mac, but too large to send") }
            outcome.image = (data, destination)
        }
        return outcome
    }

    public static let screenRecordingHint =
        "Allow Glasspad in System Settings > Privacy & Security > Screen & System Audio Recording."

    public var isRecording: Bool { recording?.isRunning == true }

    private func toggleRecording() async -> Outcome {
        if let rec = recording, rec.isRunning {
            rec.interrupt()
            recording = nil
            return Outcome(ok: true, message: "Recording saved")
        }
        let file = env.screenshotFolder().appendingPathComponent(Self.fileName("Screen Recording", date: env.now(), ext: "mov"))
        guard let p = env.start(executable: "/usr/sbin/screencapture", arguments: ["-v", "-k", file.path]) else {
            return .fail("Could not start recording")
        }
        if recordingStartCheck > .zero { try? await Task.sleep(for: recordingStartCheck) }
        guard p.isRunning else { return .fail(Self.screenRecordingHint) }
        recording = p
        return Outcome(ok: true, message: "Recording")
    }

    // MARK: Shortcuts

    /// Runs a shortcut; a missing one is named as missing rather than "failed".
    private func runShortcut(_ name: String) async -> Outcome {
        let r = await env.run(executable: "/usr/bin/shortcuts", arguments: ["run", name], timeout: 60)
        if r.ok { return .done }
        let names = await env.shortcutNames()
        if !names.isEmpty, !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return .fail("There is no shortcut named \u{201C}\(name)\u{201D} on this Mac")
        }
        if r.output == "Timed out" { return .fail("Shortcut \u{201C}\(name)\u{201D} took too long") }
        return .fail("Shortcut \u{201C}\(name)\u{201D} stopped with an error")
    }

    /// Shortcuts the user may already have for Do Not Disturb, used only when Control Center
    /// cannot be reached.
    public static let doNotDisturbShortcuts = ["Toggle Do Not Disturb", "Do Not Disturb", "Toggle Focus"]

    // MARK: System controls

    private func system(_ s: DeckSystemAction) async -> Outcome {
        switch s {
        case .lockScreen:
            if !env.lockScreen() { env.press(Keystroke(key: .character("q"), modifiers: [.command, .control])) }
            return .done
        case .sleepDisplay:
            return await tool("/usr/bin/pmset", ["displaysleepnow"], "Could not sleep the display")
        case .sleepMac:
            return await tool("/usr/bin/pmset", ["sleepnow"], "Could not sleep the Mac")
        case .toggleDarkMode:
            if let dark = env.toggleDarkMode() { return Outcome(ok: true, message: dark ? "Dark" : "Light") }
            return await tool(Self.osascript, ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"],
                              Self.automationHint)
        case .volumeUp, .volumeDown:
            guard let v = env.outputVolume else { return .fail("This sound output has no volume control") }
            // Like the volume keys: turning it up unmutes.
            if s == .volumeUp, env.outputMuted == true { _ = env.toggleOutputMute() }
            env.setOutputVolume(min(1, max(0, v + (s == .volumeUp ? Self.step : -Self.step))))
            return .done
        case .mute:
            guard env.toggleOutputMute() else { return .fail("This sound output cannot be muted") }
            return Outcome(ok: true, message: env.outputMuted.map { $0 ? "Muted" : "Sound on" })
        case .micMute:
            guard let muted = env.inputMuted else { return .fail("No microphone found") }
            guard env.setInputMuted(!muted) else { return .fail("This microphone cannot be muted") }
            return Outcome(ok: true, message: muted ? "Microphone on" : "Microphone muted")
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
            // macOS 26 replaced Launchpad with the Apps launcher; older Macs still have Launchpad.
            if await env.openApp(bundleID: "com.apple.apps.launcher") { return .done }
            return await env.openApp(bundleID: "com.apple.launchpad.launcher") ? .done : .fail("Could not open Apps")
        case .emptyTrash:
            return await tool(Self.osascript, ["-e", "tell application \"Finder\" to empty trash"], Self.automationHint)
        case .ejectAll:
            let r = env.ejectAll()
            if r.failed > 0 { return .fail("\(r.failed) disk\(r.failed == 1 ? "" : "s") could not be ejected (in use)") }
            return Outcome(ok: true, message: r.ejected == 0 ? "Nothing to eject" : nil)
        case .doNotDisturb:
            let r = await env.toggleDoNotDisturb()
            if case .failed(let why) = r {
                let names = await env.shortcutNames()
                if let name = Self.doNotDisturbShortcuts.first(where: names.contains) { return await runShortcut(name) }
                return .fail(why)
            }
            return Self.outcome(r, "Do Not Disturb")
        case .nightShift: return Self.outcome(env.toggleNightShift(), "Night Shift")
        case .keepAwake:
            let r = env.toggleKeepAwake()
            if r == .on { return Outcome(ok: true, message: "Staying awake") }
            return Self.outcome(r, "Keep Awake")
        case .notificationCenter:
            return env.openNotificationCenter() ? .done : .fail("Could not open Notification Center. " + AXUI.permissionHint)
        case .windowLeft, .windowRight, .windowTop, .windowBottom, .windowFill, .windowCenter:
            guard let placement = WindowPlacement(s) else { return .fail("Unknown window position") }
            return env.placeFrontWindow(placement).map(Outcome.fail) ?? .done
        case .windowSplit:
            return env.splitFrontWindows().map(Outcome.fail) ?? .done
        case .windowNextDisplay:
            return env.moveFrontWindowToNextDisplay().map(Outcome.fail) ?? .done
        }
    }

    /// "Night Shift is on" for the phone, or the failure.
    static func outcome(_ r: DeckSwitchResult, _ name: String) -> Outcome {
        switch r {
        case .on: Outcome(ok: true, message: "\(name) is on")
        case .off: Outcome(ok: true, message: "\(name) is off")
        case .changed: .done
        case .failed(let why): .fail(why)
        }
    }

    private func tool(_ path: String, _ args: [String], _ failure: String) async -> Outcome {
        let r = await env.run(executable: path, arguments: args, timeout: 15)
        return r.ok ? .done : .fail(failure)
    }
}
