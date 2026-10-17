import AppKit
import CoreServices
import GlasspadKit

/// Reads (and on request asks for) the Automation permission for the two players Media mode
/// controls with AppleScript: Spotify and Music.
public enum AutomationProbe {
    /// One player's answer.
    public enum Answer: Equatable, Sendable {
        case granted, denied, notDetermined
        /// Installed, but macOS can only answer while it runs.
        case notRunning
        case notInstalled
    }

    public static let players: [(name: String, bundleID: String)] = [
        ("Spotify", "com.spotify.client"),
        ("Music", "com.apple.Music"),
    ]

    /// Combines the players' answers with the apps Media mode was refused for.
    public static func combine(_ answers: [Answer], deniedApps: [String] = []) -> AutomationState {
        if !deniedApps.isEmpty || answers.contains(.denied) { return .denied }
        if answers.contains(.granted) { return .granted }
        if answers.allSatisfy({ $0 == .notInstalled }) { return .notNeeded }
        return .notDetermined
    }

    /// Never shows a prompt. Runs off the main thread: `AEDeterminePermissionToAutomateTarget`
    /// can block indefinitely (waiting on tccd or on an unresponsive player), and on the main
    /// thread that froze the whole app at launch. Gives up after `timeout` and reports
    /// `notDetermined`. A stuck call keeps one background thread, never the main one, and never
    /// more than one: later checks wait for that same call instead of starting another (each
    /// phone session asks again, and every stuck call used to keep a thread of its own).
    public static func current(deniedApps: [String] = [], timeout: TimeInterval = 2) async -> AutomationState {
        await current(deniedApps: deniedApps, timeout: timeout, gate: .live) {
            players.map { answer(bundleID: $0.bundleID, ask: false) }
        }
    }

    /// `current` with the per-player probe injected (tests use a probe that never returns).
    static func current(deniedApps: [String], timeout: TimeInterval, gate: ProbeGate = ProbeGate(),
                        probe: @escaping @Sendable () -> [Answer]) async -> AutomationState {
        let fallback: AutomationState = deniedApps.isEmpty ? .notDetermined : .denied
        // Whichever finishes first resumes; a probe that never returns only keeps its own
        // background thread busy.
        return await withCheckedContinuation { continuation in
            let once = ProbeOnce()
            gate.join(probe, once: once) { answers in
                if once.claim() { continuation.resume(returning: combine(answers, deniedApps: deniedApps)) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if once.claim() { continuation.resume(returning: fallback) }
            }
        }
    }

    /// Shows the macOS prompt for each running player not asked yet. Blocks until answered, so
    /// it runs off the main thread. Returns whether any player was running to ask.
    public static func request() async -> (state: AutomationState, askedAny: Bool) {
        let running = await MainActor.run {
            players.map { p in (p.bundleID, !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty) }
        }
        return await Task.detached(priority: .userInitiated) {
            var answers: [Answer] = []
            for (id, isRunning) in running {
                answers.append(answer(bundleID: id, ask: isRunning))
            }
            return (combine(answers), running.contains { $0.1 })
        }.value
    }

    static func answer(bundleID: String, ask: Bool) -> Answer {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return .notInstalled }
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        guard AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &target) == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .notRunning
        default: return .notDetermined
        }
    }
}

/// Lets exactly one of two racing callbacks resume a continuation.
final class ProbeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
    var isClaimed: Bool {
        lock.lock(); defer { lock.unlock() }
        return done
    }
}

/// At most one permission probe at a time. A check made while one is still running (or stuck)
/// gets that run's answers instead of starting another thread.
final class ProbeGate: @unchecked Sendable {
    /// The one the app uses.
    static let live = ProbeGate()

    private struct Waiter {
        let once: ProbeOnce
        let deliver: @Sendable ([AutomationProbe.Answer]) -> Void
    }

    private let lock = NSLock()
    /// nil while no probe runs.
    private var waiters: [Waiter]?
    private var started = 0
    private var joined = 0

    /// Probes started so far, and checks made (tests).
    var runs: Int {
        lock.lock(); defer { lock.unlock() }
        return started
    }
    var joins: Int {
        lock.lock(); defer { lock.unlock() }
        return joined
    }

    func join(_ probe: @escaping @Sendable () -> [AutomationProbe.Answer], once: ProbeOnce,
              deliver: @escaping @Sendable ([AutomationProbe.Answer]) -> Void) {
        lock.lock()
        joined += 1
        if var list = waiters {
            // Callers that already gave up are dropped, so a probe stuck for good holds no list.
            list.removeAll { $0.once.isClaimed }
            list.append(Waiter(once: once, deliver: deliver))
            waiters = list
            lock.unlock()
            return
        }
        waiters = [Waiter(once: once, deliver: deliver)]
        started += 1
        lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            let answers = probe()
            self.lock.lock()
            let list = self.waiters ?? []
            self.waiters = nil
            self.lock.unlock()
            list.forEach { $0.deliver(answers) }
        }
    }
}
