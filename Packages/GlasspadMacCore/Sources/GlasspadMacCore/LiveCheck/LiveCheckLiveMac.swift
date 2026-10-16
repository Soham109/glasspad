import AppKit
import ApplicationServices
import GlasspadKit
import IOKit.pwr_mgt

/// The real Mac behind the live check. Buttons run through the app's own `ModeRouter` and its
/// `DeckMode`, exactly as when the phone presses them; readings come from the same helpers the
/// app uses. Only the TextEdit windows it opens itself are ever moved.
@MainActor
public final class LiveCheckLiveMac: LiveCheckMac {
    private let router: ModeRouter
    private let env: LiveDeckEnvironment
    private let bringBack: () -> Void
    private var inbox: [ModeMessage] = []
    public private(set) var doNotDisturbFlips = 0
    private var mediaStarted = false

    private struct TestWindow {
        let app: AXUIElement
        let window: AXUIElement
    }
    private var testWindows: [TestWindow] = []
    private var testFiles: [URL] = []
    private var editorWasRunning = true

    /// `returnToCheck` brings the check's window back to the front.
    public init(router: ModeRouter, returnToCheck: @escaping () -> Void) {
        self.router = router
        self.env = LiveDeckEnvironment(keys: router.keys)
        self.bringBack = returnToCheck
        router.tracksSession = false
        router.send = { [weak self] in self?.inbox.append($0) }
    }

    // MARK: The phone's paths

    public func perform(_ action: DeckAction) async -> DeckMode.Outcome {
        let o = await router.deck.perform(action)
        if action == .system(.doNotDisturb), o.ok { doNotDisturbFlips += 1 }
        return o
    }

    public func phone(_ message: ModeMessage) -> [ModeMessage] {
        inbox.removeAll()
        router.handle(message)
        defer { inbox.removeAll() }
        return inbox
    }

    public func displaysState() -> DisplaysState? { router.displays?.state() }

    // MARK: Reading

    public var accessibilityAllowed: Bool { AXIsProcessTrusted() }
    public func darkMode() -> Bool? { MacSystem.isDark() }
    public func nightShift() -> Bool? { NightShift.isOn() }
    public func keepAwake() -> Bool { KeepAwake.shared.isOn }

    public func keepAwakeAssertionListed() -> Bool? {
        var out: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&out) == kIOReturnSuccess,
              let all = out?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return nil }
        let mine = all[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? []
        return mine.contains { ($0[kIOPMAssertionNameKey] as? String) == "Glasspad Keep Awake" }
    }

    public func focusInMenuBar() -> Bool? { ControlCenterFocus.focusShowsInMenuBar() }

    public func notificationCenterWindows() -> Int? {
        AXUI.app("com.apple.notificationcenterui").map { AXUI.windows($0).count }
    }

    public func outputVolume() -> Double? { AudioOutput.volume().map(Double.init) }
    public func outputMuted() -> Bool? { AudioOutput.isMuted() }
    public func inputMuted() -> Bool? { AudioInput.isMuted() }
    public func inputVolume() -> Double? { AudioInput.volume().map(Double.init) }
    public func brightness() -> Double? { Brightness.get().map(Double.init) }

    public func dock() -> LiveCheckDock {
        let d = router.macDock
        return LiveCheckDock(hidden: d.manual, hideWhileConnected: d.hideWhileConnected, connected: d.connected, isHiddenNow: d.isHidden)
    }

    public func dockRevealDelay() -> Double? {
        CFPreferencesAppSynchronize(MacDockHider.domain as CFString)
        return (CFPreferencesCopyAppValue("autohide-delay" as CFString, MacDockHider.domain as CFString) as? NSNumber)?.doubleValue
    }

    public func isRecording() -> Bool { router.deck.isRecording }

    public func nowPlaying() async -> MediaState? {
        if !mediaStarted {
            mediaStarted = true
            router.media.setActive(true)
            try? await Task.sleep(for: .seconds(1.2))
        }
        router.media.phoneWantsEverything()
        return await withCheckedContinuation { c in
            var done = false
            router.media.state { state in
                guard !done else { return }
                done = true
                c.resume(returning: state)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                guard !done else { return }
                done = true
                c.resume(returning: nil)
            }
        }
    }

    public func frontmostBundleID() -> String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    public func captures(since date: Date) -> [URL] {
        let folder = env.screenshotFolder()
        let keys: [URLResourceKey] = [.creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files.filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("Screenshot ") || name.hasPrefix("Screen Recording ") else { return false }
            let created = (try? url.resourceValues(forKeys: Set(keys)))?.creationDate ?? .distantPast
            return created >= date.addingTimeInterval(-1)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }

    public func appName(_ bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    public func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public func screens() -> [TilingScreen] { WindowMover.screens() }
    public func tileGap() -> CGFloat { WindowMover.gap() }
    public func shortcutNames() async -> [String] { await env.shortcutNames() }

    // MARK: Putting back

    public func setDarkMode(_ dark: Bool) async -> Bool {
        guard let now = MacSystem.isDark() else { return false }
        if now == dark { return true }
        if MacSystem.toggleDarkMode() == nil { _ = await router.deck.perform(.system(.toggleDarkMode)) }
        try? await Task.sleep(for: .milliseconds(500))
        return MacSystem.isDark() == dark
    }

    public func setNightShift(_ on: Bool) -> Bool {
        guard let now = NightShift.isOn() else { return false }
        if now == on { return true }
        return NightShift.toggle() == (on ? .on : .off)
    }

    public func setKeepAwake(_ on: Bool) -> Bool {
        if KeepAwake.shared.isOn == on { return true }
        return KeepAwake.shared.toggle() == (on ? .on : .off)
    }

    public func flipDoNotDisturb() async -> Bool { await perform(.system(.doNotDisturb)).ok }
    public func toggleNotificationCenter() -> Bool { ControlCenterFocus.openNotificationCenter() }
    public func setOutputVolume(_ value: Double) { AudioOutput.setVolume(Float(value)) }
    public func setOutputMuted(_ muted: Bool) { AudioOutput.setMuted(muted) }
    public func setInputMuted(_ muted: Bool) async { _ = AudioInput.setMuted(muted) }
    public func setInputVolume(_ value: Double) { _ = AudioInput.setVolume(Float32(value)) }
    public func setBrightness(_ value: Double) { Brightness.set(Float(value)) }

    public func setDock(_ d: LiveCheckDock) {
        router.macDock.setConnected(d.connected)
        router.macDock.set(MacDockState(hidden: d.hidden, hideWhileConnected: d.hideWhileConnected))
    }

    public func stopRecording() async {
        guard router.deck.isRecording else { return }
        _ = await router.deck.perform(.screenRecording)
        try? await Task.sleep(for: .seconds(2))
    }

    public func applyDisplays(_ change: DisplayChange, permanently: Bool) -> Bool {
        router.displays?.backend.apply(change, permanently: permanently) ?? false
    }

    public func restorePermanentDisplays() { router.displays?.backend.restorePermanent() }

    public func trash(_ urls: [URL]) -> Int {
        urls.filter { (try? FileManager.default.trashItem(at: $0, resultingItemURL: nil)) != nil }.count
    }

    // MARK: Throwaway windows

    static let editor = "com.apple.TextEdit"
    static let testName = "Glasspad Live Check"

    public var testWindowCount: Int { testWindows.count }

    public func openTestWindows() async -> Bool {
        guard testWindows.isEmpty else { return true }
        guard AXIsProcessTrusted(), let editorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.editor) else {
            return false
        }
        editorWasRunning = isRunning(Self.editor)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(Self.testName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = "This window belongs to the Glasspad live check. It closes by itself when the check ends.\n"
        testFiles = (1...2).map { folder.appendingPathComponent("\(Self.testName) \($0).txt") }
        for file in testFiles { try? Data(text.utf8).write(to: file) }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try? await NSWorkspace.shared.open(testFiles, withApplicationAt: editorURL, configuration: config)

        // Find them by the file each one shows, so the person's own TextEdit windows are never picked.
        for _ in 0..<50 {
            if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.editor).first?.processIdentifier {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 1)
                let windows = AXUI.elements(app, kAXWindowsAttribute)
                let found = testFiles.compactMap { file in windows.first { Self.shows(file, $0) } }
                if found.count == testFiles.count {
                    testWindows = found.map { TestWindow(app: app, window: $0) }
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard testWindows.count == testFiles.count, let main = screens().first else { return false }
        // A known size away from the edges, so every tile is a real move.
        let v = main.visible
        for (i, w) in testWindows.enumerated() {
            let frame = CGRect(x: v.minX + 120 + CGFloat(i) * 60, y: v.minY + 90 + CGFloat(i) * 50, width: 640, height: 420)
            _ = await WindowMover.set(w.window, app: w.app, to: frame)
        }
        return true
    }

    /// The window showing `file` (TextEdit names its document by URL).
    static func shows(_ file: URL, _ window: AXUIElement) -> Bool {
        if let doc = AXUI.string(window, kAXDocumentAttribute), let url = URL(string: doc) {
            return url.standardizedFileURL.resolvingSymlinksInPath().path == file.standardizedFileURL.resolvingSymlinksInPath().path
        }
        return AXUI.string(window, kAXTitleAttribute) == file.lastPathComponent
    }

    public func focusTestWindow(_ index: Int) async -> Bool {
        guard testWindows.indices.contains(index),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.editor).first else { return false }
        let w = testWindows[index]
        app.activate(options: [])
        AXUIElementSetAttributeValue(w.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(w.window, kAXRaiseAction as CFString)
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(100))
            if frontmostBundleID() == Self.editor, let focused = AXUI.element(w.app, kAXFocusedWindowAttribute),
               CFEqual(focused, w.window) { return true }
        }
        return false
    }

    public func testWindowFrame(_ index: Int) -> CGRect? {
        testWindows.indices.contains(index) ? AXUI.frame(testWindows[index].window) : nil
    }

    public func setTestWindowFrame(_ index: Int, _ frame: CGRect) async -> Bool {
        guard testWindows.indices.contains(index) else { return false }
        let w = testWindows[index]
        return await WindowMover.set(w.window, app: w.app, to: frame)
    }

    public func testWindowID(_ index: Int) -> UInt32? {
        testWindows.indices.contains(index) ? WindowMover.windowID(testWindows[index].window) : nil
    }

    public func wrapUp() async {
        if router.deck.isRecording { await stopRecording() }
        if mediaStarted { router.media.setActive(false) }
        for w in testWindows {
            if let button = AXUI.element(w.window, kAXCloseButtonAttribute) { AXUI.press(button) }
        }
        if !testWindows.isEmpty { try? await Task.sleep(for: .milliseconds(600)) }
        // Quit TextEdit only when the check opened it and nothing else of the person's is open.
        if !editorWasRunning, let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.editor).first,
           AXUI.elements(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute).isEmpty {
            app.terminate()
        }
        testWindows = []
        for file in testFiles { try? FileManager.default.removeItem(at: file) }
        testFiles = []
    }

    // MARK: Apps and pacing

    public func activate(_ bundleID: String) async -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        app.activate(options: [])
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(100))
            if frontmostBundleID() == bundleID { return true }
        }
        return false
    }

    public func returnToCheck() { bringBack() }

    public func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
}
