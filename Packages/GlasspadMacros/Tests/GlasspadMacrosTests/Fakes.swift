import Foundation
import CoreGraphics
@testable import GlasspadMacros

/// Ordered log shared by all fakes, stamped with the fake clock's time.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

final class FakeClock: MacroClock, @unchecked Sendable {
    private let lock = NSLock()
    private var now: Double = 0
    private(set) var sleeps: [Double] = []
    var onAdvance: (@Sendable (Double) -> Void)?

    func nowMs() -> Double { lock.lock(); defer { lock.unlock() }; return now }

    func sleep(ms: Double) async throws {
        try Task.checkCancellation()
        let (t, hook) = advance(ms)
        hook?(t)
        await Task.yield()
        try Task.checkCancellation()
    }

    private func advance(_ ms: Double) -> (Double, (@Sendable (Double) -> Void)?) {
        lock.withLock {
            now += ms
            sleeps.append(ms)
            return (now, onAdvance)
        }
    }

    var recordedSleeps: [Double] { lock.lock(); defer { lock.unlock() }; return sleeps }
}

final class FakeOutput: MacroEventOutput, @unchecked Sendable {
    let log: EventLog
    var onEvent: (@Sendable (String) -> Void)?
    init(log: EventLog) { self.log = log }

    private func record(_ s: String) { log.add(s); onEvent?(s) }

    func press(_ combo: KeyCombo) async throws { record("press \(combo.displayString)") }
    func type(_ text: String) async throws { record("type \(text)") }
    func moveMouse(to p: CGPoint) async throws { record("move \(Int(p.x)),\(Int(p.y))") }
    func click(_ b: MouseButton, at p: CGPoint, count: Int, modifiers: KeyModifiers) async throws {
        record("click \(b.rawValue) \(Int(p.x)),\(Int(p.y)) x\(count)\(modifiers.symbols)")
    }
    func drag(_ b: MouseButton, from: CGPoint, to: CGPoint, durationMs: Int) async throws {
        record("drag \(Int(from.x)),\(Int(from.y))->\(Int(to.x)),\(Int(to.y)) \(durationMs)ms")
    }
    func scroll(dx: Int, dy: Int) async throws { record("scroll \(dx),\(dy)") }
}

final class FakeWindows: FrontmostWindowProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var bundle: String?
    private var frame: CGRect?
    private(set) var frameQueries = 0

    init(bundle: String? = "com.apple.finder", frame: CGRect? = nil) {
        self.bundle = bundle
        self.frame = frame
    }
    func setBundle(_ b: String?) { lock.lock(); bundle = b; lock.unlock() }
    func setFrame(_ f: CGRect?) { lock.lock(); frame = f; lock.unlock() }
    func frontmostBundleID() -> String? { lock.lock(); defer { lock.unlock() }; return bundle }
    func frontmostWindowFrame() -> CGRect? {
        lock.lock(); defer { lock.unlock() }
        frameQueries += 1
        return frame
    }
}

final class FakeApps: AppLaunching, @unchecked Sendable {
    let log: EventLog
    init(log: EventLog) { self.log = log }
    func openApp(bundleID: String) async throws { log.add("openApp \(bundleID)") }
    func open(url: URL) async throws { log.add("open \(url.absoluteString)") }
}

final class FakeShortcuts: ShortcutsRunning, @unchecked Sendable {
    let log: EventLog
    var output: String? = "shortcut-output"
    init(log: EventLog) { self.log = log }
    func list() async throws -> [ShortcutInfo] { [] }
    func run(_ nameOrID: String, input: String?) async throws -> String? {
        log.add("shortcut \(nameOrID) input=\(input ?? "nil")")
        return output
    }
}

final class FakeScripts: ScriptRunning, @unchecked Sendable {
    let log: EventLog
    init(log: EventLog) { self.log = log }
    func runAppleScript(_ source: String) async throws -> String? { log.add("applescript \(source)"); return "as-out" }
    func runShell(_ command: String, timeoutMs: Int) async throws -> String { log.add("shell \(command)"); return "sh-out" }
}

final class FakeClipboard: ClipboardWriting, @unchecked Sendable {
    let log: EventLog
    init(log: EventLog) { self.log = log }
    func setString(_ text: String) { log.add("clipboard \(text)") }
}

final class FakeNotifier: Notifying, @unchecked Sendable {
    let log: EventLog
    init(log: EventLog) { self.log = log }
    func notify(title: String, body: String) async throws { log.add("notify \(title): \(body)") }
}

final class FakeMonitor: UserInputMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    var available = true
    private(set) var started = 0
    private(set) var stopped = 0

    func start(onUserInput: @escaping @Sendable () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        started += 1
        guard available else { return false }
        handler = onUserInput
        return true
    }
    func stop() { lock.lock(); stopped += 1; handler = nil; lock.unlock() }
    /// Simulates the user touching the real mouse.
    func fire() { lock.lock(); let h = handler; lock.unlock(); h?() }
}

struct Harness {
    let log = EventLog()
    let clock = FakeClock()
    let windows: FakeWindows
    let output: FakeOutput
    let monitor = FakeMonitor()
    let shortcuts: FakeShortcuts
    let player: MacroPlayer

    init(windows: FakeWindows = FakeWindows(), clock: (any MacroClock)? = nil) {
        self.windows = windows
        output = FakeOutput(log: log)
        shortcuts = FakeShortcuts(log: log)
        player = MacroPlayer(environment: MacroEnvironment(
            output: output, windows: windows, apps: FakeApps(log: log), shortcuts: shortcuts,
            scripts: FakeScripts(log: log), clipboard: FakeClipboard(log: log), notifier: FakeNotifier(log: log),
            clock: clock ?? self.clock, inputMonitor: monitor))
    }
}

final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [[String]] = []
    let respond: @Sendable ([String]) -> ProcessResult
    init(_ respond: @escaping @Sendable ([String]) -> ProcessResult) { self.respond = respond }
    func run(_ executable: String, _ arguments: [String], timeoutMs: Int) async throws -> ProcessResult {
        lock.withLock { calls.append(arguments) }
        return respond(arguments)
    }
    var allCalls: [[String]] { lock.lock(); defer { lock.unlock() }; return calls }
}

final class FakeRecordingSource: RecordingEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (RecordedEvent) -> Void)?
    var failWith: MacroError?
    private(set) var running = false

    func start(_ handler: @escaping @Sendable (RecordedEvent) -> Void) throws {
        if let failWith { throw failWith }
        lock.lock(); self.handler = handler; running = true; lock.unlock()
    }
    func stop() { lock.lock(); handler = nil; running = false; lock.unlock() }
    func emit(_ e: RecordedEvent) { lock.lock(); let h = handler; lock.unlock(); h?(e) }
    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }
}

final class FakeSecureInput: SecureInputChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    func set(_ v: Bool) { lock.lock(); on = v; lock.unlock() }
    func isSecureInputEnabled() -> Bool { lock.lock(); defer { lock.unlock() }; return on }
}

final class FakeFrontmostObserver: FrontmostAppObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?
    private var handler: (@Sendable (String?) -> Void)?
    init(current: String?) { self.current = current }
    func currentBundleID() -> String? { lock.lock(); defer { lock.unlock() }; return current }
    func start(_ onChange: @escaping @Sendable (String?) -> Void) { lock.lock(); handler = onChange; lock.unlock() }
    func stop() { lock.lock(); handler = nil; lock.unlock() }
    func activate(_ id: String?) {
        lock.lock(); current = id; let h = handler; lock.unlock()
        h?(id)
    }
}

@MainActor
final class FakeHotkeys: HotkeyRegistering {
    var registered: [KeyCombo] = []
    var taken: Set<KeyCombo> = []
    var handler: (@MainActor (KeyCombo) -> Void)?
    func setHotkeys(_ combos: [KeyCombo], handler: @escaping @MainActor (KeyCombo) -> Void) -> [KeyCombo] {
        registered = combos.filter { !taken.contains($0) }
        self.handler = handler
        return combos.filter { taken.contains($0) }
    }
    func removeAll() { registered = [] }
    func press(_ c: KeyCombo) { if registered.contains(c) { handler?(c) } }
}

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("glasspad-macros-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}
