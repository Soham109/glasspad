import AppKit
import GlasspadKit

/// One display's setup, as far as the check can change it.
public struct LiveCheckDisplaySetup: Equatable, Sendable {
    public var id: UInt32
    public var resolutionID: Int32?
    public var mirrorOf: UInt32?
    public var origin: CGPoint
    public var isMain: Bool

    public init(id: UInt32, resolutionID: Int32?, mirrorOf: UInt32?, origin: CGPoint, isMain: Bool) {
        self.id = id
        self.resolutionID = resolutionID
        self.mirrorOf = mirrorOf
        self.origin = origin
        self.isMain = isMain
    }

    init(_ d: MacDisplay) {
        self.init(id: d.id, resolutionID: d.resolutionID, mirrorOf: d.mirrorOf, origin: d.frame.origin, isMain: d.isMain)
    }
}

/// Everything a step could change, read before it runs. After the step (whatever the answer,
/// and also when the check is stopped half way) `LiveCheckRestorer` puts back whatever differs.
public struct LiveCheckSnapshot: Equatable, Sendable {
    public var darkMode: Bool?
    public var nightShift: Bool?
    public var keepAwake: Bool
    public var doNotDisturbFlips: Int
    public var notificationCenterWindows: Int?
    public var outputVolume: Double?
    public var outputMuted: Bool?
    public var inputMuted: Bool?
    public var inputVolume: Double?
    public var brightness: Double?
    public var dock: LiveCheckDock
    public var displays: [LiveCheckDisplaySetup]
    public var recording: Bool
    /// The check's own windows (nil where one is not open).
    public var testWindows: [CGRect?]
    /// Only read for steps that play or pause, since asking the players takes a moment.
    public var playing: Bool?

    @MainActor
    public static func capture(_ mac: LiveCheckMac, playback: Bool = false) async -> LiveCheckSnapshot {
        LiveCheckSnapshot(
            darkMode: mac.darkMode(), nightShift: mac.nightShift(), keepAwake: mac.keepAwake(),
            doNotDisturbFlips: mac.doNotDisturbFlips, notificationCenterWindows: mac.notificationCenterWindows(),
            outputVolume: mac.outputVolume(), outputMuted: mac.outputMuted(), inputMuted: mac.inputMuted(),
            inputVolume: mac.inputVolume(), brightness: mac.brightness(), dock: mac.dock(),
            displays: (mac.displaysState()?.displays ?? []).map(LiveCheckDisplaySetup.init),
            recording: mac.isRecording(),
            testWindows: (0..<mac.testWindowCount).map { mac.testWindowFrame($0) },
            playing: playback ? await mac.nowPlaying()?.isPlaying : nil)
    }
}

/// One thing put back (or not).
public struct LiveCheckRestoreNote: Equatable, Sendable {
    public var ok: Bool
    public var text: String

    public init(ok: Bool, _ text: String) {
        self.ok = ok
        self.text = text
    }
}

/// Compares the Mac with a snapshot and puts back only what differs, checking each one after.
@MainActor
public enum LiveCheckRestorer {
    /// Volume and brightness count as unchanged within this (the Mac rounds them).
    static let level: Double = 0.01
    /// How long a display change takes to show up in the readings.
    static let displaySettle: Double = 2

    public static func restore(_ s: LiveCheckSnapshot, on mac: LiveCheckMac) async -> [LiveCheckRestoreNote] {
        var notes: [LiveCheckRestoreNote] = []
        func note(_ ok: Bool, _ done: String, _ failed: String) {
            notes.append(LiveCheckRestoreNote(ok: ok, ok ? done : failed))
        }

        if s.recording == false, mac.isRecording() {
            await mac.stopRecording()
            note(!mac.isRecording(), "Stopped the screen recording", "Could not stop the screen recording")
        }
        if let before = s.darkMode, let now = mac.darkMode(), now != before {
            let ok = await mac.setDarkMode(before)
            note(ok && mac.darkMode() == before, "Put back \(before ? "Dark" : "Light") appearance",
                 "Could not put back \(before ? "Dark" : "Light") appearance")
        }
        if let before = s.nightShift, let now = mac.nightShift(), now != before {
            let ok = mac.setNightShift(before)
            note(ok && mac.nightShift() == before, "Turned Night Shift \(before ? "on" : "off") again",
                 "Could not turn Night Shift \(before ? "on" : "off") again")
        }
        if mac.keepAwake() != s.keepAwake {
            let ok = mac.setKeepAwake(s.keepAwake)
            note(ok && mac.keepAwake() == s.keepAwake, "Turned Keep Awake \(s.keepAwake ? "on" : "off") again",
                 "Could not turn Keep Awake \(s.keepAwake ? "on" : "off") again")
        }
        if (mac.doNotDisturbFlips - s.doNotDisturbFlips) % 2 != 0 {
            let ok = await mac.flipDoNotDisturb()
            note(ok, "Switched Do Not Disturb back", "Could not switch Do Not Disturb back. Check Control Center.")
        }
        if let before = s.notificationCenterWindows, let now = mac.notificationCenterWindows(), now > before {
            _ = mac.toggleNotificationCenter()
            await mac.pause(0.8)
            let after = mac.notificationCenterWindows() ?? now
            note(after <= before, "Closed Notification Center", "Could not close Notification Center")
        }
        if let before = s.outputMuted, let now = mac.outputMuted(), now != before {
            mac.setOutputMuted(before)
            note(mac.outputMuted() == before, before ? "Muted the sound again" : "Unmuted the sound again",
                 before ? "Could not mute the sound again" : "Could not unmute the sound again")
        }
        if let before = s.outputVolume, let now = mac.outputVolume(), abs(now - before) > level {
            mac.setOutputVolume(before)
            let ok = mac.outputVolume().map { abs($0 - before) <= level } ?? false
            note(ok, "Put the volume back to \(percent(before))", "Could not put the volume back to \(percent(before))")
        }
        if let before = s.inputVolume, let now = mac.inputVolume(), abs(now - before) > level {
            mac.setInputVolume(before)
            let ok = mac.inputVolume().map { abs($0 - before) <= level } ?? false
            note(ok, "Put the microphone level back to \(percent(before))",
                 "Could not put the microphone level back to \(percent(before))")
        }
        if let before = s.inputMuted, let now = mac.inputMuted(), now != before {
            await mac.setInputMuted(before)
            note(mac.inputMuted() == before, before ? "Muted the microphone again" : "Turned the microphone back on",
                 before ? "Could not mute the microphone again" : "Could not turn the microphone back on")
        }
        if let before = s.brightness, let now = mac.brightness(), abs(now - before) > level {
            mac.setBrightness(before)
            let ok = mac.brightness().map { abs($0 - before) <= level } ?? false
            note(ok, "Put the brightness back to \(percent(before))", "Could not put the brightness back to \(percent(before))")
        }
        if mac.dock() != s.dock {
            mac.setDock(s.dock)
            let now = mac.dock()
            note(now == s.dock,
                 s.dock.isHiddenNow ? "Hid the Dock again" : "Put the Dock back",
                 s.dock.isHiddenNow ? "Could not hide the Dock again" : "Could not put the Dock back")
        }
        notes += await restoreDisplays(s.displays, on: mac)
        for (i, frame) in s.testWindows.enumerated() {
            guard let frame, let now = mac.testWindowFrame(i), !WindowTiling.isClose(now, frame) else { continue }
            mac.setTestWindowFrame(i, frame)
            let ok = mac.testWindowFrame(i).map { WindowTiling.isClose($0, frame) } ?? false
            note(ok, "Put the test window back", "Could not put the test window back")
        }
        if let before = s.playing, let now = await mac.nowPlaying()?.isPlaying, now != before {
            _ = await mac.perform(.system(.playPause))
            await mac.pause(1.5)
            let ok = await mac.nowPlaying()?.isPlaying == before
            note(ok, before ? "Started playback again" : "Paused playback again",
                 before ? "Could not start playback again" : "Could not pause playback again")
        }
        return notes
    }

    /// Resolution and mirroring first (macOS's own undo, then each display by hand), then where
    /// the displays sit and which is the main one.
    static func restoreDisplays(_ before: [LiveCheckDisplaySetup], on mac: LiveCheckMac) async -> [LiveCheckRestoreNote] {
        guard !before.isEmpty else { return [] }
        var notes: [LiveCheckRestoreNote] = []
        func current() -> [UInt32: LiveCheckDisplaySetup] {
            Dictionary((mac.displaysState()?.displays ?? []).map { ($0.id, LiveCheckDisplaySetup($0)) }, uniquingKeysWith: { a, _ in a })
        }
        func modeDiffers(_ now: [UInt32: LiveCheckDisplaySetup]) -> [LiveCheckDisplaySetup] {
            before.filter { b in now[b.id].map { $0.resolutionID != b.resolutionID || $0.mirrorOf != b.mirrorOf } ?? false }
        }
        if mac.displaysState()?.pending != nil {
            mac.phone(.displayCommand(id: UUID(), command: .revertChanges))
            await mac.pause(displaySettle)
        }
        var differs = modeDiffers(current())
        if !differs.isEmpty {
            mac.restorePermanentDisplays()
            await mac.pause(displaySettle)
            differs = modeDiffers(current())
            for b in differs {
                if let now = current()[b.id], now.mirrorOf != b.mirrorOf {
                    _ = mac.applyDisplays(.mirror(display: b.id, of: b.mirrorOf), permanently: true)
                }
                if let id = b.resolutionID, current()[b.id]?.resolutionID != id {
                    _ = mac.applyDisplays(.resolution(display: b.id, id: id), permanently: true)
                }
            }
            if !differs.isEmpty { await mac.pause(displaySettle) }
            let left = modeDiffers(current())
            notes.append(LiveCheckRestoreNote(ok: left.isEmpty, left.isEmpty ? "Put the display settings back"
                : "Could not put the display settings back. Check System Settings > Displays."))
        }
        let now = current()
        let moved = before.filter { b in now[b.id].map { $0.origin != b.origin || $0.isMain != b.isMain } ?? false }
        if !moved.isEmpty {
            // Each display back at its old origin; the one at 0, 0 is the main display again.
            let origins = before.filter { $0.mirrorOf == nil && now[$0.id] != nil }
                .map { DisplayOrigin(display: $0.id, origin: $0.origin) }
            _ = mac.applyDisplays(.origins(origins), permanently: true)
            await mac.pause(displaySettle)
            let after = current()
            let ok = before.allSatisfy { b in after[b.id].map { $0.origin == b.origin && $0.isMain == b.isMain } ?? true }
            notes.append(LiveCheckRestoreNote(ok: ok, ok ? "Put the displays back where they were"
                : "Could not put the displays back where they were. Check System Settings > Displays."))
        }
        return notes
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}
