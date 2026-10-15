import AppKit
import GlasspadKit

/// Deck buttons config, stored as JSON at
/// ~/Library/Application Support/Glasspad/deck.json. Only buttons defined here can run; the
/// phone sends a button id, never an action, so a phone cannot inject commands.
public struct DeckConfig: Codable, Equatable, Sendable {
    public var version: Int
    /// Shell-script buttons run only when the user turned this on explicitly on the Mac.
    public var allowShellCommands: Bool
    public var buttons: [DeckButton]

    public init(version: Int = 1, allowShellCommands: Bool = false, buttons: [DeckButton] = DeckConfig.starterButtons) {
        self.version = version
        self.allowShellCommands = allowShellCommands
        self.buttons = buttons
    }

    public static let starterButtons: [DeckButton] = [
        DeckButton(title: "Safari", symbol: "safari", action: .openApp(bundleID: "com.apple.Safari")),
        DeckButton(title: "Screenshot", symbol: "camera.viewfinder",
                   action: .keystroke(Keystroke(key: .character("5"), modifiers: [.command, .shift]))),
        DeckButton(title: "Lock", symbol: "lock",
                   action: .keystroke(Keystroke(key: .character("q"), modifiers: [.command, .control]))),
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
        return cfg
    }

    public func save(to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}

/// Side effects of Deck actions, injectable so tests never launch anything.
public protocol DeckEnvironment: AnyObject {
    func openApp(bundleID: String) -> Bool
    func open(url: URL) -> Bool
    func run(executable: String, arguments: [String]) -> (ok: Bool, output: String)
    func press(_ keystroke: Keystroke)
}

@MainActor
public final class DeckMode {
    public private(set) var config: DeckConfig
    private let env: DeckEnvironment
    private let url: URL

    public init(env: DeckEnvironment, url: URL = DeckConfig.defaultURL()) {
        self.env = env
        self.url = url
        self.config = DeckConfig.load(from: url)
    }

    public func reload() { config = DeckConfig.load(from: url) }

    public func update(_ cfg: DeckConfig) throws {
        try cfg.save(to: url)
        config = cfg
    }

    /// Runs the button and returns the result message for the phone.
    public func run(id: UUID) -> ModeMessage {
        guard let button = config.buttons.first(where: { $0.id == id }) else {
            return .deckResult(id: id, ok: false, message: "Button not found")
        }
        let (ok, message) = perform(button.action)
        return .deckResult(id: id, ok: ok, message: ok ? nil : message)
    }

    func perform(_ action: DeckAction) -> (Bool, String?) {
        switch action {
        case .openApp(let bundleID):
            return env.openApp(bundleID: bundleID) ? (true, nil) : (false, "App not found")
        case .openURL(let s):
            guard let u = URL(string: s), u.scheme != nil, u.scheme?.lowercased() != "file" else { return (false, "Invalid URL") }
            return env.open(url: u) ? (true, nil) : (false, "Could not open URL")
        case .runShortcut(let name):
            let r = env.run(executable: "/usr/bin/shortcuts", arguments: ["run", name])
            return (r.ok, r.ok ? nil : "Shortcut failed")
        case .keystroke(let k):
            env.press(k)
            return (true, nil)
        case .shellScript(let script):
            guard config.allowShellCommands else { return (false, "Shell commands are turned off on the Mac") }
            let r = env.run(executable: "/bin/zsh", arguments: ["-c", script])
            return (r.ok, r.ok ? nil : String(r.output.suffix(200)))
        }
    }
}

/// The real environment.
public final class LiveDeckEnvironment: DeckEnvironment {
    private let keys: KeysMode
    public init(keys: KeysMode) { self.keys = keys }

    public func openApp(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        return true
    }

    public func open(url: URL) -> Bool { NSWorkspace.shared.open(url) }

    public func run(executable: String, arguments: [String]) -> (ok: Bool, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, error.localizedDescription) }
        // Deck actions are short; wait off the main thread would be nicer, but the phone
        // expects a result. A 10 s cap keeps a hung script from freezing the app.
        let deadline = Date().addingTimeInterval(10)
        while p.isRunning, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        if p.isRunning { p.terminate(); return (false, "Timed out") }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus == 0, out)
    }

    public func press(_ keystroke: Keystroke) { keys.press(keystroke) }
}
