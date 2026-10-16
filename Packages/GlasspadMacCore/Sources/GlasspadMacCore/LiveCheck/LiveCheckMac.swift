import AppKit
import GlasspadKit

/// The Mac as the live check sees it: the phone's own paths in (Deck and Remote buttons through
/// `DeckMode.perform`, every other message through `ModeRouter.handle`), readings out, and what
/// it needs to put things back. `LiveCheckLiveMac` is the real one; tests use a fake, so nothing
/// on the Mac changes while they run.
@MainActor
public protocol LiveCheckMac: AnyObject {
    // MARK: The phone's paths

    /// A Deck or Remote control, run by the code the phone's buttons run.
    func perform(_ action: DeckAction) async -> DeckMode.Outcome
    /// A message from the phone, handled by the Mac's router. Returns what the Mac answered
    /// straight away (a Displays result, for example).
    @discardableResult
    func phone(_ message: ModeMessage) -> [ModeMessage]
    /// What the Displays screen would be sent now.
    func displaysState() -> DisplaysState?

    // MARK: Reading

    var accessibilityAllowed: Bool { get }
    func darkMode() -> Bool?
    func nightShift() -> Bool?
    func keepAwake() -> Bool
    /// True when macOS lists Glasspad's "keep the display awake" assertion.
    func keepAwakeAssertionListed() -> Bool?
    /// Every Do Not Disturb switch the check made (Do Not Disturb has no public reading).
    var doNotDisturbFlips: Int { get }
    /// True while a Focus shows in the menu bar; nil when Control Center cannot be read.
    func focusInMenuBar() -> Bool?
    /// Notification Center's open windows; nil when it cannot be read.
    func notificationCenterWindows() -> Int?
    func outputVolume() -> Double?
    func outputMuted() -> Bool?
    func inputMuted() -> Bool?
    func inputVolume() -> Double?
    func brightness() -> Double?
    func dock() -> LiveCheckDock
    /// com.apple.dock `autohide-delay` as the Dock reads it.
    func dockRevealDelay() -> Double?
    func isRecording() -> Bool
    /// What plays now, as Media and Remote see it; nil when nothing answered.
    func nowPlaying() async -> MediaState?
    func frontmostBundleID() -> String?
    /// Screenshots and screen recordings saved since `date`, in the screenshot folder.
    func captures(since date: Date) -> [URL]
    func fileSize(_ url: URL) -> Int?
    /// The app's name as Finder shows it; nil when it is not installed.
    func appName(_ bundleID: String) -> String?
    func isRunning(_ bundleID: String) -> Bool
    func screens() -> [TilingScreen]
    func tileGap() -> CGFloat
    func shortcutNames() async -> [String]

    // MARK: Putting back

    func setDarkMode(_ dark: Bool) async -> Bool
    func setNightShift(_ on: Bool) -> Bool
    func setKeepAwake(_ on: Bool) -> Bool
    /// Presses the Do Not Disturb switch once more, the way the button does.
    func flipDoNotDisturb() async -> Bool
    /// Presses the menu bar clock, which opens and closes Notification Center.
    func toggleNotificationCenter() -> Bool
    func setOutputVolume(_ value: Double)
    func setOutputMuted(_ muted: Bool)
    func setInputMuted(_ muted: Bool) async
    func setInputVolume(_ value: Double)
    func setBrightness(_ value: Double)
    func setDock(_ dock: LiveCheckDock)
    func stopRecording() async
    func applyDisplays(_ change: DisplayChange, permanently: Bool) -> Bool
    func restorePermanentDisplays()
    /// Moves files to the Trash; how many went.
    @discardableResult
    func trash(_ urls: [URL]) -> Int

    // MARK: Throwaway windows

    /// Opens the check's own TextEdit windows (two), never one of the person's.
    func openTestWindows() async -> Bool
    var testWindowCount: Int { get }
    /// Brings one of them to the front; false when it would not come forward.
    func focusTestWindow(_ index: Int) async -> Bool
    func testWindowFrame(_ index: Int) -> CGRect?
    @discardableResult
    func setTestWindowFrame(_ index: Int, _ frame: CGRect) -> Bool
    func testWindowID(_ index: Int) -> UInt32?

    /// Closes the test windows and anything else the check opened or started.
    func wrapUp() async

    // MARK: Apps and pacing

    func activate(_ bundleID: String) async -> Bool
    /// Brings the check's own window back to the front.
    func returnToCheck()
    func pause(_ seconds: Double) async
}

/// The Mac Dock switches, and whether a phone counts as connected.
public struct LiveCheckDock: Equatable, Sendable {
    public var hidden: Bool
    public var hideWhileConnected: Bool
    public var connected: Bool
    /// The Dock is hidden right now.
    public var isHiddenNow: Bool

    public init(hidden: Bool, hideWhileConnected: Bool, connected: Bool, isHiddenNow: Bool) {
        self.hidden = hidden
        self.hideWhileConnected = hideWhileConnected
        self.connected = connected
        self.isHiddenNow = isHiddenNow
    }
}
