import Foundation
import CoreGraphics

/// Posts synthetic input. The default is `CGEventOutput`; the Mac app may
/// supply its own (for example one that shares GlasspadMacCore's event source).
/// Implementations must tag every event with `MacroEventMarker.userData` so the
/// recorder and the user-input guard can tell playback from the real user.
public protocol MacroEventOutput: Sendable {
    func press(_ combo: KeyCombo) async throws
    func type(_ text: String) async throws
    func moveMouse(to point: CGPoint) async throws
    func click(_ button: MouseButton, at point: CGPoint, count: Int, modifiers: KeyModifiers) async throws
    func drag(_ button: MouseButton, from: CGPoint, to: CGPoint, durationMs: Int) async throws
    func scroll(dx: Int, dy: Int) async throws
}

/// Value stamped into `kCGEventSourceUserData` of every event a macro posts.
public enum MacroEventMarker {
    public static let userData: Int64 = 0x474C_5350_4D41_4352 // "GLSPMACR"
}

/// Reads the frontmost app and its focused window.
public protocol FrontmostWindowProviding: Sendable {
    func frontmostBundleID() -> String?
    /// The focused window's frame in global Quartz coordinates (top-left origin).
    func frontmostWindowFrame() -> CGRect?
}

public protocol AppLaunching: Sendable {
    func openApp(bundleID: String) async throws
    func open(url: URL) async throws
}

public struct ShortcutInfo: Hashable, Codable, Sendable {
    public var name: String
    public var identifier: String?
    /// nil when the shortcut is not in a folder.
    public var folder: String?

    public init(name: String, identifier: String?, folder: String?) {
        self.name = name
        self.identifier = identifier
        self.folder = folder
    }
}

public protocol ShortcutsRunning: Sendable {
    func list() async throws -> [ShortcutInfo]
    /// Runs a shortcut and returns its text output, or nil if it produced none.
    func run(_ nameOrID: String, input: String?) async throws -> String?
}

public protocol ScriptRunning: Sendable {
    func runAppleScript(_ source: String) async throws -> String?
    func runShell(_ command: String, timeoutMs: Int) async throws -> String
}

public protocol ClipboardWriting: Sendable {
    func setString(_ text: String)
}

public protocol Notifying: Sendable {
    func notify(title: String, body: String) async throws
}

/// Time for the player. The real one sleeps; the test one only records.
public protocol MacroClock: Sendable {
    /// Monotonic milliseconds.
    func nowMs() -> Double
    func sleep(ms: Double) async throws
}

/// Watches the real mouse and keyboard while a macro plays, so the user can
/// take over by simply touching them.
public protocol UserInputMonitoring: Sendable {
    /// Starts watching. Returns false if the monitor cannot run (for example
    /// Input Monitoring is not granted); playback then continues unguarded and
    /// says so in its result.
    func start(onUserInput: @escaping @Sendable () -> Void) -> Bool
    func stop()
}

/// Reports whether secure keyboard input is on (a password field is focused,
/// or an app such as Terminal has Secure Keyboard Entry enabled).
public protocol SecureInputChecking: Sendable {
    func isSecureInputEnabled() -> Bool
}

public struct ContinuousMacroClock: MacroClock {
    private let start = ContinuousClock.now
    public init() {}
    public func nowMs() -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
    public func sleep(ms: Double) async throws {
        guard ms > 0 else { try Task.checkCancellation(); return }
        try await Task.sleep(for: .microseconds(Int64(ms * 1000)))
    }
}
