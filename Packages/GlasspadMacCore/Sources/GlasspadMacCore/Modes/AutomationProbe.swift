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

    /// Never shows a prompt.
    @MainActor
    public static func current(deniedApps: [String] = []) -> AutomationState {
        combine(players.map { answer(bundleID: $0.bundleID, ask: false) }, deniedApps: deniedApps)
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
