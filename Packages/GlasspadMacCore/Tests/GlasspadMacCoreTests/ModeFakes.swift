import AppKit
import Foundation
import GlasspadKit
@testable import GlasspadMacCore

/// A pretend com.apple.dock domain.
final class FakeDefaults: DefaultsStore {
    var values: [String: [String: Any]] = [:]
    var writes = 0
    var syncs = 0
    func value(forKey key: String, domain: String) -> Any? { values[domain]?[key] }
    func set(_ value: Any?, forKey key: String, domain: String) {
        writes += 1
        var d = values[domain] ?? [:]
        d[key] = value
        values[domain] = d
    }
    func synchronize(domain: String) { syncs += 1 }
}

final class FakeRunner: ProcessRunning {
    var calls: [(String, [String])] = []
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        calls.append((executable, arguments))
        return (0, "")
    }
}

@MainActor
enum FakeDockHider {
    static func make(dock: FakeDefaults = FakeDefaults(), suite: String = "glasspad-tests-\(UUID().uuidString)")
        -> (hider: MacDockHider, dock: FakeDefaults, own: UserDefaults, runner: FakeRunner) {
        let own = UserDefaults(suiteName: suite)!
        let runner = FakeRunner()
        return (MacDockHider(dock: dock, own: own, runner: runner), dock, own, runner)
    }
}

/// A pretend Mac for Dock mode: nothing is opened, hidden or quit for real.
@MainActor
final class FakeWorkspace: DockWorkspace {
    var persistent: Any?
    var recent: Any?
    var running: [DockMode.RunningApp] = []
    var front: String?
    var lsURLs: [String: [URL]] = [:]
    var installed: [(bundleID: String, name: String, url: URL?)] = []
    var existing: Set<String> = []
    var bundleIDs: [String: String] = [:]
    var launchErrors: [String: String] = [:]
    /// What `frontmostBundleID` says after an activation (nil = activation is ignored).
    var frontAfterActivate: String?

    var launches: [(path: String, reopen: Bool)] = []
    var activated: [pid_t] = []
    var forcedFront: [pid_t] = []
    var hidden: [pid_t] = []
    var unhidden: [pid_t] = []
    var terminated: [pid_t] = []
    var revealed: [URL] = []
    var iconRenders = 0

    func dockPreferences() -> (persistent: Any?, recent: Any?) { (persistent, recent) }
    func runningApps() -> [DockMode.RunningApp] { running }
    func frontmostBundleID() -> String? { front }
    func applicationURLs(bundleID: String) -> [URL] { lsURLs[bundleID] ?? [] }
    func installedApps() -> [(bundleID: String, name: String, url: URL?)] { installed }
    func fileExists(_ url: URL) -> Bool { existing.contains(url.standardizedFileURL.path) }
    func bundleIdentifier(at url: URL) -> String? { bundleIDs[url.standardizedFileURL.path] }
    func displayName(_ url: URL) -> String? { url.deletingPathExtension().lastPathComponent }
    func modificationDate(_ url: URL) -> Date? { Date(timeIntervalSince1970: 1_700_000_000) }
    func iconPNG(for url: URL, pixels: Int) -> Data? {
        iconRenders += 1
        return DockMode.renderPNG(NSImage(size: NSSize(width: 1024, height: 1024)), pixels: pixels)
    }
    func launch(_ url: URL, reopen: Bool, completion: @escaping @MainActor (String?) -> Void) {
        launches.append((url.standardizedFileURL.path, reopen))
        completion(launchErrors[url.standardizedFileURL.path])
    }
    func activate(pid: pid_t) -> Bool {
        activated.append(pid)
        if let f = frontAfterActivate { front = f }
        return true
    }
    func bringToFront(pid: pid_t) -> Bool { forcedFront.append(pid); return true }
    func hide(pid: pid_t) -> Bool { hidden.append(pid); return true }
    func unhide(pid: pid_t) -> Bool { unhidden.append(pid); return true }
    func terminate(pid: pid_t) -> Bool { terminated.append(pid); return true }
    func reveal(_ url: URL) { revealed.append(url) }
    func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) { block() }
}

@MainActor
final class FakeProcess: DeckProcess {
    var isRunning = true
    var interrupted = 0
    func interrupt() { interrupted += 1; isRunning = false }
}

/// A pretend Mac for Deck buttons. Records every call; never runs anything.
@MainActor
final class FakeDeckEnvironment: DeckEnvironment {
    var opened: [String] = []
    var urls: [URL] = []
    var runs: [(String, [String])] = []
    var started: [(String, [String])] = []
    var pressed: [Keystroke] = []
    var typed: [String] = []
    var macros: [UUID] = []
    var mediaCommands: [MediaCommand] = []
    var existing: Set<String> = []
    var runResult: (ok: Bool, output: String) = (true, "")
    /// Files that "appear" when screencapture runs (the fake writes nothing).
    var captureCreatesFile = true
    var outputVolume: Double? = 0.5
    var inputMuted: Bool? = false
    var brightness: Double? = 0.5
    var outputs = ["MacBook Pro Speakers", "AirPods Pro"]
    var selectedOutput: String?
    var ejectResult = (ejected: 2, failed: 0)
    var frontWindow: UInt32? = 4242
    var clock = Date(timeIntervalSince1970: 1_760_540_712)   // 2025-10-15 15:05:12 UTC
    var lastProcess: FakeProcess?
    var copiedToClipboard: [URL] = []
    var mutedToggles = 0
    let home = URL(fileURLWithPath: "/Users/test")
    let shots = URL(fileURLWithPath: "/Users/test/Pictures/Shots")

    func openApp(bundleID: String) async -> Bool { opened.append(bundleID); return bundleID != "missing" }
    func open(url: URL) -> Bool { urls.append(url); return true }
    func fileExists(_ url: URL) -> Bool { existing.contains(url.path) }
    var homeDirectory: URL { home }
    func run(executable: String, arguments: [String], timeout: TimeInterval) async -> (ok: Bool, output: String) {
        runs.append((executable, arguments))
        if executable == "/usr/sbin/screencapture", captureCreatesFile, let path = arguments.last { existing.insert(path) }
        return runResult
    }
    func start(executable: String, arguments: [String]) -> DeckProcess? {
        started.append((executable, arguments))
        let p = FakeProcess()
        lastProcess = p
        return p
    }
    func press(_ keystroke: Keystroke) { pressed.append(keystroke) }
    func type(_ text: String) { typed.append(text) }
    func runMacro(_ id: UUID) async -> (ok: Bool, message: String?) { macros.append(id); return (true, nil) }
    func media(_ command: MediaCommand) { mediaCommands.append(command) }
    func setOutputVolume(_ value: Double) { outputVolume = value }
    func toggleOutputMute() -> Bool { mutedToggles += 1; return true }
    func setInputMuted(_ muted: Bool) -> Bool { inputMuted = muted; return true }
    func setBrightness(_ value: Double) { brightness = value }
    func audioOutputs() -> [String] { outputs }
    func setAudioOutput(name: String) -> Bool {
        guard outputs.contains(name) else { return false }
        selectedOutput = name
        return true
    }
    func ejectAll() -> (ejected: Int, failed: Int) { ejectResult }
    func screenshotFolder() -> URL { shots }
    func frontWindowID() -> UInt32? { frontWindow }
    func now() -> Date { clock }
    func phoneImageData(_ url: URL) -> Data? { Data("image:\(url.lastPathComponent)".utf8) }
    func copyImageToClipboard(_ url: URL) -> Bool { copiedToClipboard.append(url); return true }
    func shortcutNames() async -> [String] { ["Focus On", "Focus Off"] }
}
