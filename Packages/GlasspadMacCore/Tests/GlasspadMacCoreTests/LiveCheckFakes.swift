import AppKit
import Foundation
import GlasspadKit
@testable import GlasspadMacCore

/// A pretend Mac for the live check: every button changes this object and nothing else, and
/// time only passes when the check pauses (so a 15 second revert takes no time at all).
@MainActor
final class FakeLiveCheckMac: LiveCheckMac {
    // State.
    var dark: Bool? = false
    var night: Bool? = false
    var awake = false
    var dnd = false
    private(set) var doNotDisturbFlips = 0
    var ncWindows: Int? = 0
    var volume: Double? = 0.5
    var muted: Bool? = false
    var micMuted: Bool? = false
    var micVolume: Double? = 0.8
    var bright: Double? = 0.7
    var dockState = LiveCheckDock(hidden: false, hideWhileConnected: false, connected: false, isHiddenNow: false)
    var revealDelay: Double?
    var recording = false
    var playing = true
    var track = 0
    var front: String? = "com.apple.Terminal"
    var running: Set<String> = ["com.apple.Music"]
    var installed: [String: String] = ["com.apple.Music": "Music", "com.apple.TextEdit": "TextEdit"]
    var shortcuts = ["Morning"]
    var files: [URL: Int] = [:]
    var trashed: [URL] = []
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var log: [String] = []

    // Displays: a built-in display and one to its right.
    var displays: [MacDisplay] = [
        MacDisplay(id: 1, name: "Built-in Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                   visibleFrame: CGRect(x: 0, y: 32, width: 1512, height: 950), isMain: true, isBuiltIn: true, brightness: 0.7,
                   resolutions: [DisplayResolution(id: 10, width: 1312, height: 848), DisplayResolution(id: 11, width: 1512, height: 982, isDefault: true),
                                 DisplayResolution(id: 12, width: 1800, height: 1169)], resolutionID: 11),
        MacDisplay(id: 2, name: "Studio Display", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                   visibleFrame: CGRect(x: 1512, y: 25, width: 2560, height: 1415), isMain: false),
    ]
    private var permanent: [MacDisplay] = []
    private var pending: (summary: String, deadline: Date)?

    // Test windows.
    var windows: [CGRect] = []
    var frontWindow: Int?
    /// Setters that do nothing, to see a failed restore reported.
    var stuck: Set<String> = []

    init() { permanent = displays }

    // MARK: The phone's paths

    func perform(_ action: DeckAction) async -> DeckMode.Outcome {
        log.append("perform \(action)")
        switch action {
        case .system(let s): return system(s)
        case .screenshot(let shot):
            let name = DeckMode.fileName("Screenshot", date: clock, ext: "png")
            let url = URL(fileURLWithPath: "/fake/\(shot.area.rawValue) \(name)")
            files[url] = 1000
            return DeckMode.Outcome(ok: true, image: shot.sendToPhone.map { (Data([1]), $0) })
        case .screenRecording:
            if recording {
                recording = false
                files[URL(fileURLWithPath: "/fake/\(DeckMode.fileName("Screen Recording", date: clock, ext: "mov"))")] = 5000
                return DeckMode.Outcome(ok: true, message: "Recording saved")
            }
            recording = true
            return DeckMode.Outcome(ok: true, message: "Recording")
        case .runShortcut(let name):
            return DeckMode.Outcome(ok: false, message: shortcuts.contains(name) ? nil : "There is no shortcut named \u{201C}\(name)\u{201D} on this Mac")
        default:
            return DeckMode.Outcome(ok: true)
        }
    }

    private func system(_ s: DeckSystemAction) -> DeckMode.Outcome {
        switch s {
        case .toggleDarkMode:
            dark?.toggle()
            return DeckMode.Outcome(ok: true, message: dark == true ? "Dark" : "Light")
        case .doNotDisturb:
            dnd.toggle()
            doNotDisturbFlips += 1
            return DeckMode.Outcome(ok: true, message: "Do Not Disturb is \(dnd ? "on" : "off")")
        case .nightShift:
            night?.toggle()
            return DeckMode.Outcome(ok: true, message: "Night Shift is \(night == true ? "on" : "off")")
        case .keepAwake:
            awake.toggle()
            return DeckMode.Outcome(ok: true, message: awake ? "Staying awake" : "Keep Awake is off")
        case .notificationCenter:
            ncWindows = 1
        case .volumeUp, .volumeDown:
            if s == .volumeUp, muted == true { muted = false }
            volume = volume.map { min(1, max(0, $0 + (s == .volumeUp ? DeckMode.step : -DeckMode.step))) }
        case .mute: muted?.toggle()
        case .micMute: micMuted?.toggle()
        case .brightnessUp, .brightnessDown:
            bright = bright.map { min(1, max(0, $0 + (s == .brightnessUp ? DeckMode.step : -DeckMode.step))) }
        case .playPause: playing.toggle()
        case .nextTrack: track += 1
        case .previousTrack: track -= 1
        case .windowLeft, .windowRight, .windowTop, .windowBottom, .windowFill, .windowCenter:
            guard let i = frontWindow, let p = WindowPlacement(s), let screen = screen(of: windows[i]) else { return .init(ok: false) }
            windows[i] = WindowTiling.frame(p, window: windows[i], in: screen.visible, gap: tileGap())
        case .windowSplit:
            guard let i = frontWindow, let screen = screen(of: windows[i]) else { return .init(ok: false) }
            let halves = WindowTiling.split(in: screen.visible, gap: tileGap())
            windows[i] = halves.left
            windows[1 - i] = halves.right
        case .windowNextDisplay:
            let all = screens()
            guard let i = frontWindow, let from = WindowTiling.screenIndex(for: windows[i], in: all),
                  let to = WindowTiling.nextScreenIndex(after: from, in: all) else { return .init(ok: false) }
            windows[i] = WindowTiling.moved(windows[i], from: all[from].visible, to: all[to].visible)
        default: break
        }
        return DeckMode.Outcome(ok: true)
    }

    private func screen(of frame: CGRect) -> TilingScreen? {
        WindowTiling.screenIndex(for: frame, in: screens()).map { screens()[$0] }
    }

    func phone(_ message: ModeMessage) -> [ModeMessage] {
        log.append("phone \(message)")
        switch message {
        case .displayCommand(let id, let command):
            let r = display(command)
            return [.displaysResult(id: id, ok: r == nil, message: r)]
        case .windowCommand(let id, let wid, let command):
            guard let s = displaysState(), let moves = s.frames(for: command, window: wid) else {
                return [.displaysResult(id: id, ok: false, message: "That window has closed.")]
            }
            for m in moves { windows[Int(m.window) - 100] = m.frame }
            return [.displaysResult(id: id, ok: true, message: nil)]
        case .mediaSetVolume(let v): volume = v
        case .macDockSet(let d):
            dockState.hidden = d.hidden
            dockState.hideWhileConnected = d.hideWhileConnected
            dockState.isHiddenNow = d.hidden
            revealDelay = d.hidden ? MacDockHider.hiddenDelay : nil
        case .mediaCommand(.playPause): playing.toggle()
        default: break
        }
        return []
    }

    private func display(_ command: DisplayCommand) -> String? {
        func index(_ id: UInt32) -> Int? { displays.firstIndex { $0.id == id } }
        switch command {
        case .resolution(let id, let mode):
            guard let i = index(id) else { return "gone" }
            displays[i].resolutionID = mode
            pending = ("resolution", clock.addingTimeInterval(TimeInterval(DisplaysMode.keepSeconds)))
        case .mirror(let id, let of):
            guard let i = index(id) else { return "gone" }
            displays[i].mirrorOf = of
            pending = ("mirror", clock.addingTimeInterval(TimeInterval(DisplaysMode.keepSeconds)))
        case .revertChanges:
            pending = nil
            displays = permanent
        case .keepChanges:
            pending = nil
            permanent = displays
        case .makeMain(let id):
            guard let m = displays.first(where: { $0.id == id })?.frame.origin else { return "gone" }
            setOrigins(displays.map { DisplayOrigin(display: $0.id, origin: CGPoint(x: $0.frame.minX - m.x, y: $0.frame.minY - m.y)) })
        case .arrange(let origins):
            let main = displays.first(where: \.isMain)?.id ?? 1
            setOrigins(DisplayGeometry.normalized(origins, main: main))
        case .brightness(_, let value):
            bright = value
        }
        return nil
    }

    private func setOrigins(_ origins: [DisplayOrigin]) {
        for o in origins {
            guard let i = displays.firstIndex(where: { $0.id == o.display }) else { continue }
            let f = displays[i].frame, v = displays[i].visibleFrame
            displays[i].frame.origin = o.origin
            displays[i].visibleFrame = v.offsetBy(dx: o.origin.x - f.minX, dy: o.origin.y - f.minY)
            displays[i].isMain = o.origin == .zero
        }
        permanent = displays
    }

    func displaysState() -> DisplaysState? {
        if let p = pending, clock >= p.deadline {
            pending = nil
            displays = permanent
        }
        let ws = windows.enumerated().map { MacWindow(id: UInt32(100 + $0.offset), bundleID: "com.apple.TextEdit", appName: "TextEdit",
                                                      title: "Glasspad Live Check \($0.offset + 1).txt", frame: $0.element) }
        let left = pending.map { max(0, Int($0.deadline.timeIntervalSince(clock).rounded(.up))) } ?? 0
        return DisplaysState(displays: displays, windows: ws, tileMargin: Double(tileGap()),
                             pending: pending.map { PendingDisplayChange(summary: $0.summary, secondsLeft: left) })
    }

    // MARK: Reading

    var accessibilityAllowed: Bool { true }
    func darkMode() -> Bool? { dark }
    func nightShift() -> Bool? { night }
    func keepAwake() -> Bool { awake }
    func keepAwakeAssertionListed() -> Bool? { awake }
    func focusInMenuBar() -> Bool? { dnd }
    func notificationCenterWindows() -> Int? { ncWindows }
    func outputVolume() -> Double? { volume }
    func outputMuted() -> Bool? { muted }
    func inputMuted() -> Bool? { micMuted }
    func inputVolume() -> Double? { micVolume }
    func brightness() -> Double? { bright }
    func dock() -> LiveCheckDock { dockState }
    func dockRevealDelay() -> Double? { revealDelay }
    func isRecording() -> Bool { recording }

    func nowPlaying() async -> MediaState? {
        MediaState(title: "Song \(track)", isPlaying: playing, duration: 200, elapsed: 50,
                   sourceBundleID: "com.apple.Music", sourceName: "Music", canSeek: true)
    }

    func frontmostBundleID() -> String? { front }
    func captures(since date: Date) -> [URL] { files.keys.sorted { $0.path < $1.path } }
    func fileSize(_ url: URL) -> Int? { files[url] }
    func appName(_ bundleID: String) -> String? { installed[bundleID] }
    func isRunning(_ bundleID: String) -> Bool { running.contains(bundleID) }

    func screens() -> [TilingScreen] {
        displays.filter { $0.mirrorOf == nil }.sorted { a, _ in a.isMain }.map { TilingScreen(frame: $0.frame, visible: $0.visibleFrame) }
    }

    func tileGap() -> CGFloat { 8 }
    func shortcutNames() async -> [String] { shortcuts }

    // MARK: Putting back

    func setDarkMode(_ value: Bool) async -> Bool {
        guard !stuck.contains("dark") else { return false }
        dark = value
        return true
    }

    func setNightShift(_ on: Bool) -> Bool { night = on; return true }
    func setKeepAwake(_ on: Bool) -> Bool { awake = on; return true }
    func flipDoNotDisturb() async -> Bool { await perform(.system(.doNotDisturb)).ok }

    func toggleNotificationCenter() -> Bool {
        ncWindows = ncWindows == 0 ? 1 : 0
        return true
    }

    func setOutputVolume(_ value: Double) { volume = value }
    func setOutputMuted(_ value: Bool) { muted = value }
    func setInputMuted(_ value: Bool) async { micMuted = value }
    func setInputVolume(_ value: Double) { micVolume = value }
    func setBrightness(_ value: Double) { bright = value }
    func setDock(_ d: LiveCheckDock) {
        dockState = d
        revealDelay = d.isHiddenNow ? MacDockHider.hiddenDelay : nil
    }

    func stopRecording() async {
        if recording { _ = await perform(.screenRecording) }
    }

    func applyDisplays(_ change: DisplayChange, permanently: Bool) -> Bool {
        switch change {
        case .origins(let origins): setOrigins(origins)
        case .resolution(let id, let mode):
            if let i = displays.firstIndex(where: { $0.id == id }) { displays[i].resolutionID = mode }
        case .mirror(let id, let of):
            if let i = displays.firstIndex(where: { $0.id == id }) { displays[i].mirrorOf = of }
        }
        if permanently { permanent = displays }
        return true
    }

    func restorePermanentDisplays() {
        pending = nil
        displays = permanent
    }

    func trash(_ urls: [URL]) -> Int {
        for u in urls { files[u] = nil }
        trashed += urls
        return urls.count
    }

    // MARK: Throwaway windows

    var testWindowCount: Int { windows.count }

    func openTestWindows() async -> Bool {
        if windows.isEmpty { windows = [CGRect(x: 120, y: 120, width: 640, height: 420), CGRect(x: 180, y: 170, width: 640, height: 420)] }
        return true
    }

    func focusTestWindow(_ index: Int) async -> Bool {
        guard windows.indices.contains(index) else { return false }
        frontWindow = index
        front = "com.apple.TextEdit"
        return true
    }

    func testWindowFrame(_ index: Int) -> CGRect? { windows.indices.contains(index) ? windows[index] : nil }

    func setTestWindowFrame(_ index: Int, _ frame: CGRect) -> Bool {
        windows[index] = frame
        return true
    }

    func testWindowID(_ index: Int) -> UInt32? { UInt32(100 + index) }

    func wrapUp() async {
        log.append("wrap up")
        windows = []
    }

    // MARK: Apps and pacing

    func activate(_ bundleID: String) async -> Bool {
        guard running.contains(bundleID) else { return false }
        front = bundleID
        return true
    }

    func returnToCheck() { front = "com.soham109.glasspad" }

    func pause(_ seconds: Double) async { clock = clock.addingTimeInterval(seconds) }

    /// Everything the check may change, to compare before and after.
    var everything: String {
        "\(dark as Any) \(night as Any) \(awake) \(dnd) \(ncWindows as Any) \(volume as Any) \(muted as Any) \(micMuted as Any) "
            + "\(micVolume as Any) \(bright as Any) \(dockState) \(displays) \(recording) \(playing)"
    }
}
