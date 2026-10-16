import AppKit
import GlasspadKit
import GlasspadMacCore
import SwiftUI
import XCTest
@testable import Glasspad

/// The Live Check window in each of its states, drawn with a Mac that only pretends.
extension SnapshotTests {
    func testLiveCheck() async throws {
        let model = Fixtures.model(try Fixtures.macros())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gp-live-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        func runner(_ ids: [String]? = nil, mac: StillMac = StillMac()) -> LiveCheckRunner {
            let all = LiveCheckSteps.all()
            let steps = ids.map { ids in ids.compactMap { id in all.first { $0.id == id } } } ?? all
            let header = LiveCheckReport.Header(started: Date(), mac: "Soham's MacBook Pro", system: "macOS 26.0",
                                                app: "Version 0.1.0 (1)", displays: 1, disruptive: false)
            return LiveCheckRunner(steps: steps, mac: mac, includeDisruptive: false, header: header, folder: folder)
        }
        func shot(_ r: LiveCheckRunner, _ name: String, accessibility: Bool = true) throws {
            try shoot(LiveCheckView(runner: r, accessibility: accessibility, done: {}), model: model, size: nil,
                      name: "live-check-\(name)", chrome: .window)
        }

        let intro = runner()
        try shot(intro, "intro")
        try shot(intro, "intro-no-accessibility", accessibility: false)

        let r = runner()
        r.start()
        try shot(r, "ready")
        await r.run()
        try shot(r, "asking")
        await r.answer(true)
        try shot(r, "ready-after-pass")

        let one = runner(["window-next-display"])
        one.start()
        try shot(one, "ready-unavailable")

        let end = runner(["dark-mode", "night-shift"])
        end.start()
        await end.run()
        await end.answer(true)
        await end.run()
        await end.answer(false, note: "Too subtle to see")
        try shot(end, "finished")
    }
}

/// Answers every reading with a fixed value, and only flips its own switches when a button runs.
@MainActor
final class StillMac: LiveCheckMac {
    var dark = false
    var night = false

    func perform(_ action: DeckAction) async -> DeckMode.Outcome {
        switch action {
        case .system(.toggleDarkMode):
            dark.toggle()
            return DeckMode.Outcome(ok: true, message: dark ? "Dark" : "Light")
        case .system(.nightShift):
            night.toggle()
            return DeckMode.Outcome(ok: true, message: "Night Shift is \(night ? "on" : "off")")
        default:
            return DeckMode.Outcome(ok: true)
        }
    }

    func phone(_ message: ModeMessage) -> [ModeMessage] { [] }
    func displaysState() -> DisplaysState? { nil }
    var accessibilityAllowed: Bool { true }
    func darkMode() -> Bool? { dark }
    func nightShift() -> Bool? { night }
    func keepAwake() -> Bool { false }
    func keepAwakeAssertionListed() -> Bool? { nil }
    var doNotDisturbFlips: Int { 0 }
    func focusInMenuBar() -> Bool? { nil }
    func notificationCenterWindows() -> Int? { nil }
    func outputVolume() -> Double? { nil }
    func outputMuted() -> Bool? { nil }
    func inputMuted() -> Bool? { nil }
    func inputVolume() -> Double? { nil }
    func brightness() -> Double? { nil }
    func dock() -> LiveCheckDock { LiveCheckDock(hidden: false, hideWhileConnected: false, connected: false, isHiddenNow: false) }
    func dockRevealDelay() -> Double? { nil }
    func isRecording() -> Bool { false }
    func nowPlaying() async -> MediaState? { nil }
    func frontmostBundleID() -> String? { nil }
    func captures(since date: Date) -> [URL] { [] }
    func fileSize(_ url: URL) -> Int? { nil }
    func appName(_ bundleID: String) -> String? { nil }
    func isRunning(_ bundleID: String) -> Bool { false }
    func screens() -> [TilingScreen] { [] }
    func tileGap() -> CGFloat { 0 }
    func shortcutNames() async -> [String] { [] }
    func setDarkMode(_ value: Bool) async -> Bool { dark = value; return true }
    func setNightShift(_ on: Bool) -> Bool { night = on; return true }
    func setKeepAwake(_ on: Bool) -> Bool { true }
    func flipDoNotDisturb() async -> Bool { true }
    func toggleNotificationCenter() -> Bool { true }
    func setOutputVolume(_ value: Double) {}
    func setOutputMuted(_ muted: Bool) {}
    func setInputMuted(_ muted: Bool) async {}
    func setInputVolume(_ value: Double) {}
    func setBrightness(_ value: Double) {}
    func setDock(_ dock: LiveCheckDock) {}
    func stopRecording() async {}
    func applyDisplays(_ change: DisplayChange, permanently: Bool) -> Bool { true }
    func restorePermanentDisplays() {}
    func trash(_ urls: [URL]) -> Int { 0 }
    func openTestWindows() async -> Bool { false }
    var testWindowCount: Int { 0 }
    func focusTestWindow(_ index: Int) async -> Bool { false }
    func testWindowFrame(_ index: Int) -> CGRect? { nil }
    func setTestWindowFrame(_ index: Int, _ frame: CGRect) -> Bool { false }
    func testWindowID(_ index: Int) -> UInt32? { nil }
    func wrapUp() async {}
    func activate(_ bundleID: String) async -> Bool { false }
    func returnToCheck() {}
    func pause(_ seconds: Double) async {}
}
