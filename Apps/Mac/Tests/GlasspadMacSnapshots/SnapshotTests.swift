import AppKit
import GlasspadKit
import GlasspadMacCore
import GlasspadMacros
import SwiftUI
import XCTest
@testable import Glasspad

/// Debug-only snapshot harness for the Mac app's screens.
///
/// Draws every popover state and Settings pane with fixed fake state (no server, no Keychain,
/// no event posting, no defaults writes), in light and dark, to PNGs in /tmp/gpmac. It is not
/// part of scripts/test.sh. Run it with:
///
///     GLASSPAD_SNAPSHOTS=1 swift test --package-path Apps/Mac \
///         --scratch-path ~/Library/Caches/glasspad-build/GlasspadMacDebug
///
/// Macro fixtures (the shipped starters) are seeded into a fresh folder under /tmp/gpmac.
@MainActor
final class SnapshotTests: XCTestCase {
    /// GLASSPAD_SNAPSHOT_DIR moves the PNGs elsewhere, so parallel checkouts do not share them.
    static let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GLASSPAD_SNAPSHOT_DIR"] ?? "/tmp/gpmac",
                         isDirectory: true)

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["GLASSPAD_SNAPSHOTS"] == "1" else {
            throw XCTSkip("Set GLASSPAD_SNAPSHOTS=1 to draw the snapshot PNGs.")
        }
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
    }

    func testPopover() throws {
        let macros = try Fixtures.macros()
        let w = PopoverView.width

        let connected = Fixtures.model(macros)
        connected.link = .connected(rttMs: 3.1)
        connected.connectedPhoneName = "Soham's iPhone"
        try shoot(PopoverView(), model: connected, width: w, name: "popover-connected", chrome: .popover)

        let fair = Fixtures.model(macros)
        fair.link = .connected(rttMs: 26)
        fair.stats.rttMedianMs = 26
        fair.stats.rttP95Ms = 70
        fair.connectedPhoneName = "Soham's iPhone"
        try shoot(PopoverView(), model: fair, width: w, name: "popover-fair-signal", chrome: .popover)

        // The iPhone's battery at the end of its row: 42%, low, and charging.
        for (percent, charging, name) in [(42, false, "42"), (15, false, "15"), (64, true, "charging")] {
            let battery = Fixtures.model(macros)
            battery.link = .connected(rttMs: 3.1)
            battery.connectedPhoneName = "Soham's iPhone"
            battery.phoneBattery = PhoneBattery(percent: percent, charging: charging)
            try shoot(PopoverView(), model: battery, width: w, name: "popover-battery-\(name)", chrome: .popover)
        }

        let setup = Fixtures.model(macros)
        setup.link = .searching
        setup.accessibilityTrusted = false
        setup.automationDenied = ["Spotify"]
        setup.automation = .denied
        try shoot(PopoverView(), model: setup, width: w, name: "popover-needs-permissions", chrome: .popover)

        let pairing = Fixtures.model(macros)
        pairing.link = .searching
        pairing.phones = []
        pairing.pairing = Fixtures.waiting
        try shoot(PopoverView(), model: pairing, width: w, name: "popover-pairing", chrome: .popover)

        let paired = Fixtures.model(macros)
        paired.link = .connecting
        paired.pairing = .paired(phoneName: "Soham's iPhone")
        try shoot(PopoverView(), model: paired, width: w, name: "popover-pairing-paired", chrome: .popover)

        let expired = Fixtures.model(macros)
        expired.link = .searching
        expired.phones = []
        expired.pairing = .expired
        try shoot(PopoverView(), model: expired, width: w, name: "popover-pairing-expired", chrome: .popover)

        let failed = Fixtures.model(macros)
        failed.link = .searching
        failed.pairing = .failed(message: "This Mac could not save the pairing to the Keychain.")
        try shoot(PopoverView(), model: failed, width: w, name: "popover-pairing-failed", chrome: .popover)

        let firstRun = Fixtures.model(macros)
        firstRun.link = .searching
        firstRun.phones = []
        try shoot(PopoverView(), model: firstRun, width: w, name: "popover-first-run", chrome: .popover)

        // A real first launch: nothing paired and nothing allowed yet.
        let fresh = Fixtures.model(macros)
        fresh.link = .searching
        fresh.phones = []
        fresh.accessibilityTrusted = false
        fresh.automation = .notDetermined
        try shoot(PopoverView(), model: fresh, width: w, name: "popover-first-run-nothing-granted", chrome: .popover)

        let paused = Fixtures.model(macros)
        paused.link = .idle
        paused.isPaused = true
        paused.dock.hidden = true
        try shoot(PopoverView(), model: paused, width: w, name: "popover-paused", chrome: .popover)
    }

    func testWelcome() throws {
        let macros = try Fixtures.macros()
        let size = WelcomeView.size
        let fresh = Fixtures.model(macros)
        fresh.link = .searching
        fresh.phones = []
        fresh.accessibilityTrusted = false
        fresh.automation = .notDetermined
        try shoot(WelcomeView(icon: Fixtures.appIcon, start: .hello), model: fresh, size: size,
                  name: "welcome-1-hello", chrome: .window)
        try shoot(WelcomeView(icon: Fixtures.appIcon, start: .permissions), model: fresh, size: size,
                  name: "welcome-2-permissions-needed", chrome: .window)

        let half = Fixtures.model(macros)
        half.link = .searching
        half.phones = []
        half.automation = .notDetermined
        try shoot(WelcomeView(icon: Fixtures.appIcon, start: .permissions), model: half, size: size,
                  name: "welcome-2-permissions-accessibility-allowed", chrome: .window)

        let waiting = Fixtures.model(macros)
        waiting.link = .searching
        waiting.phones = []
        waiting.pairing = Fixtures.waiting
        try shoot(WelcomeView(icon: Fixtures.appIcon, start: .pair, fixedTime: 3.1), model: waiting, size: size,
                  name: "welcome-3-pair", chrome: .window)

        let done = Fixtures.model(macros)
        done.link = .connected(rttMs: 3)
        done.automation = .granted
        done.pairing = .paired(phoneName: "Soham's iPhone")
        try shoot(WelcomeView(icon: Fixtures.appIcon, start: .pair, fixedTime: 3.1), model: done, size: size,
                  name: "welcome-3-paired", chrome: .window)
    }

    /// The pairing code's motion as numbered frames (GLASSPAD_SNAPSHOT_DIR/frames), to turn into a
    /// video and check for jumps: three seconds alive, then the gather into the check.
    func testPairingCodeFrames() throws {
        guard ProcessInfo.processInfo.environment["GLASSPAD_FRAMES"] == "1" else { throw XCTSkip("Set GLASSPAD_FRAMES=1.") }
        let dir = Self.out.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let message = Fixtures.pairingURL.absoluteString
        for dark in [false, true] {
            for i in 0..<(60 * 5) {
                let t = Double(i) / 60
                let gathering = t >= 3
                let view = PairingFrameHarness(message: message, time: t,
                                               gather: gathering ? (t - 3) / PairingPattern.gatherDuration : 0)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
                    XCTFail("no frame \(i)")
                    return
                }
                try png.write(to: dir.appendingPathComponent(String(format: "%@-%04d.png", dark ? "dark" : "light", i)))
            }
        }
    }

    func testSettingsPanes() throws {
        let macros = try Fixtures.macros()
        let model = Fixtures.model(macros)
        model.link = .connected(rttMs: 3.1)
        model.connectedPhoneName = "Soham's iPhone"
        model.launchAtLogin = true
        model.dock.hideWhileConnected = true
        model.stats.framesReceived = 184_220
        model.stats.heartbeatsReceived = 912
        model.stats.replayDrops = 2
        model.settings.tuning = TrackpadTuning(pointerSpeed: 1.5, acceleration: .mac, scrollSpeed: 1,
                                               momentumStrength: 0.75, clickHaptic: 1, forceClickHaptic: 0.6,
                                               dragLockHaptic: 0)
        // One gesture moved to its shortcut by the user, and a refused clipboard pull.
        var prefs = GesturePreferences()
        prefs.set(.keyboardShortcut, for: .spaces)
        model.gesturePreferences = prefs
        model.capabilities = model.capabilities.applying(prefs)
        model.clipboardRefusal = ClipboardLimits.tooLargeMessage(bytes: 5 << 20)

        for tab in SettingsTab.allCases where tab != .macros && tab != .about {
            try shoot(tab.pane, model: model, size: tab.size, name: "settings-\(tab.rawValue)", chrome: .window)
        }
        try shoot(AboutPane(icon: Fixtures.appIcon, version: "Version 0.1.0 (1)"), model: model, size: SettingsTab.about.size,
                  name: "settings-about", chrome: .window)
        // Whole forms, for review: the real panes scroll.
        try shoot(TrackpadPane(), model: model, size: CGSize(width: 520, height: 1500), name: "full-trackpad", chrome: .window)
        try shoot(AdvancedPane(diagnosticsExpanded: true), model: model, size: CGSize(width: 520, height: 1500),
                  name: "full-advanced", chrome: .window)
        try shoot(MacrosSettings(page: .macros), model: model, size: SettingsTab.macros.size,
                  name: "settings-macros", chrome: .window)
        try shoot(MacrosSettings(page: .profiles), model: model, size: SettingsTab.macros.size,
                  name: "settings-macros-profiles", chrome: .window)

        let needs = Fixtures.model(macros)
        needs.link = .searching
        needs.accessibilityTrusted = false
        needs.automationDenied = ["Spotify"]
        needs.automation = .denied
        needs.launchNeedsApproval = true
        try shoot(GeneralPane(), model: needs, size: SettingsTab.general.size,
                  name: "settings-general-needs-permissions", chrome: .window)

        let empty = Fixtures.model(macros)
        empty.link = .searching
        empty.phones = []
        try shoot(IPhonePane(), model: empty, size: SettingsTab.iphone.size, name: "settings-iphone-empty", chrome: .window)

        let battery = Fixtures.model(macros)
        battery.link = .connected(rttMs: 3.1)
        battery.connectedPhoneName = "Soham's iPhone"
        battery.phoneBattery = PhoneBattery(percent: 42, charging: false)
        try shoot(IPhonePane(), model: battery, size: SettingsTab.iphone.size, name: "settings-iphone-battery", chrome: .window)

        let pairing = Fixtures.model(macros)
        pairing.pairing = Fixtures.waiting
        try shoot(PairingSheet(), model: pairing, width: 360, name: "sheet-pairing", chrome: .window)
        pairing.pairing = .expired
        try shoot(PairingSheet(), model: pairing, width: 360, name: "sheet-pairing-expired", chrome: .window)

        try shoot(StepEditorSheet(step: .keystroke(KeyCombo("t", [.command, .shift])), isNew: false) { _ in },
                  model: model, width: 440, name: "sheet-step-keystroke", chrome: .window)
        try shoot(StepEditorSheet(step: .keystroke(KeyCombo(.special(.space), [.command])), isNew: false) { _ in },
                  model: model, width: 440, name: "sheet-step-keystroke-space", chrome: .window)
        try shoot(StepEditorSheet(step: .openApp(bundleID: "com.apple.Safari"), isNew: false) { _ in },
                  model: model, width: 440, name: "sheet-step-open-app", chrome: .window)
        try shoot(StepEditorSheet(step: .click(button: .left, at: .screen(640, 400), count: 2, modifiers: []), isNew: true) { _ in },
                  model: model, width: 440, name: "sheet-step-click", chrome: .window)
        try shoot(RecordingIndicatorView(macros: macros), model: model, width: nil, name: "recording-indicator", chrome: .desktop)
    }

    // MARK: Drawing

    enum Chrome { case popover, window, desktop }

    func shoot<V: View>(_ view: V, model: AppModel, width: CGFloat?, name: String, chrome: Chrome) throws {
        try shoot(view, model: model, size: nil, width: width, name: name, chrome: chrome)
    }

    func shoot<V: View>(_ view: V, model: AppModel, size: CGSize?, width: CGFloat? = nil,
                                name: String, chrome: Chrome) throws {
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            let root = Framed(chrome: chrome, size: size, width: width) { view }
                .environmentObject(model)
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.solidSurfaces, true)
            let host = NSHostingView(rootView: root)
            host.appearance = appearance
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 800),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = appearance
            window.isReleasedWhenClosed = false
            window.contentView = host
            var fit = host.fittingSize
            if let size { fit = CGSize(width: size.width, height: size.height) }
            window.setContentSize(fit)
            host.frame = NSRect(origin: .zero, size: fit)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            host.layoutSubtreeIfNeeded()

            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                XCTFail("no bitmap for \(name)")
                return
            }
            appearance.performAsCurrentDrawingAppearance {
                host.cacheDisplay(in: host.bounds, to: rep)
            }
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: Self.out.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            window.close()
        }
    }
}

/// Puts a view on the surface it really sits on: a popover panel, a window, or the desktop.
private struct Framed<Content: View>: View {
    let chrome: SnapshotTests.Chrome
    let size: CGSize?
    let width: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch chrome {
        case .popover:
            content()
                .frame(width: width)
                .background(Color(nsColor: .windowBackgroundColor))
        case .window:
            content()
                .frame(width: size?.width ?? width, height: size?.height)
                .background(Color(nsColor: .windowBackgroundColor))
        case .desktop:
            content()
                .padding(24)
                .background(Color(nsColor: .underPageBackgroundColor))
        }
    }
}

// MARK: - Fixtures

@MainActor
enum Fixtures {
    static let pairingURL = PairingPayload(macID: UUID(uuidString: "6F1C2A4E-3B5D-4C7E-9F10-2A3B4C5D6E7F")!,
                                           macName: "Soham's MacBook Pro",
                                           pairKey: Data((0..<32).map { UInt8($0 * 7 & 0xFF) })).url
    static let waiting = PairingPhase.waiting(url: pairingURL, expiresAt: Date(timeIntervalSince1970: 1_900_000_000))

    static func model(_ macros: MacroCoordinator) -> AppModel {
        let m = AppModel(macName: "Soham's MacBook Pro", macros: macros,
                         capabilities: SynthCapabilities.select { $0 != .rotate },
                         settings: .macDefault, actions: .init())
        m.phones = [
            StoredPhone(phoneID: "phone-1", phoneName: "Soham's iPhone", pairKey: Data(count: 32),
                        pairedAt: Date(timeIntervalSince1970: 1_788_000_000)),
            StoredPhone(phoneID: "phone-2", phoneName: "Test iPhone 15", pairKey: Data(count: 32),
                        pairedAt: Date(timeIntervalSince1970: 1_790_100_000)),
        ]
        m.stats.rttMedianMs = 3.1
        m.stats.rttP95Ms = 6.4
        m.stats.rttSamples = 120
        return m
    }

    /// A macro coordinator over a fresh folder of the shipped starter macros and profiles.
    static func macros() throws -> MacroCoordinator {
        let dir = SnapshotTests.out.appendingPathComponent("fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let engine = MacroEngine(store: MacroStore(directory: dir.appendingPathComponent("macros")),
                                 profileStore: ProfileStore(file: dir.appendingPathComponent("profiles.json")),
                                 switcher: ProfileSwitcher(observer: FixedFrontApp()),
                                 hotkeys: nil)
        let c = MacroCoordinator(engine: engine)
        c.start(seedStarters: true)
        return c
    }

    static var appIcon: NSImage {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@1x.png")
        return NSImage(contentsOf: url) ?? NSImage()
    }
}

/// Pretends Safari is in front, so the matching starter profile is the active one.
private final class FixedFrontApp: FrontmostAppObserving, @unchecked Sendable {
    func currentBundleID() -> String? { "com.apple.Safari" }
    func start(_ onChange: @escaping @Sendable (String?) -> Void) { onChange("com.apple.Safari") }
    func stop() {}
}

/// One frame of the code on a window, at a set moment of its motion and gather.
private struct PairingFrameHarness: View {
    let message: String
    let time: Double
    let gather: Double

    var body: some View {
        PairingCodeView(message: message, size: 260, phase: gather > 0 ? .gathered(since: .distantPast) : .live,
                        fixedTime: time, fixedGather: gather > 0 ? min(1, gather) : nil)
            .padding(30)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
