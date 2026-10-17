import AppKit
import ApplicationServices
import IOKit.pwr_mgt

/// What a Mac switch did: its new state when known.
public enum DeckSwitchResult: Equatable, Sendable {
    case on, off
    /// It changed, but the Mac does not say which way.
    case changed
    case failed(String)
}

// MARK: - Do Not Disturb

/// Do Not Disturb through Control Center, the same switch the user would click. Apple keeps the
/// Focus service to its own apps (the private DoNotDisturb framework answers anyone else with an
/// XPC error), and Shortcuts needs a shortcut the user made, so this is the one way that works
/// with no setup. It uses the Accessibility permission Glasspad already has.
///
/// Control Center names its parts with stable identifiers (in every language):
/// `com.apple.menuextra.controlcenter` (menu bar item), `com.apple.menuextra.focusmode` (the
/// Focus menu bar item, shown while a Focus is on by default), `controlcenter-focus-modes` (the
/// Focus tile) and `focus-mode-activity-<mode id>` (one switch per Focus, Do Not Disturb is
/// `com.apple.donotdisturb.mode.default`).
@MainActor
enum ControlCenterFocus {
    nonisolated static let controlCenterApp = "com.apple.controlcenter"
    nonisolated static let controlCenterItem = "com.apple.menuextra.controlcenter"
    nonisolated static let focusItem = "com.apple.menuextra.focusmode"
    nonisolated static let clockItem = "com.apple.menuextra.clock"
    nonisolated static let focusTile = "controlcenter-focus-modes"
    nonisolated static let doNotDisturbMode = "com.apple.donotdisturb.mode.default"

    /// The Do Not Disturb switch inside Control Center or the Focus menu.
    nonisolated static func isDoNotDisturbSwitch(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return identifier.hasPrefix("focus-mode-activity-") && identifier.hasSuffix(doNotDisturbMode)
            || identifier == doNotDisturbMode
    }

    nonisolated static func isFocusTile(_ identifier: String?) -> Bool { identifier == focusTile }

    /// The menu bar items Control Center owns.
    static func menuBarItems(_ app: AXUIElement) -> [AXUIElement] {
        guard let bar = AXUI.element(app, "AXExtrasMenuBar") else { return [] }
        return AXUI.children(bar)
    }

    static func item(_ id: String, in app: AXUIElement) -> AXUIElement? {
        menuBarItems(app).first { AXUI.identifier($0) == id }
    }

    /// True while Focus shows in the menu bar (macOS shows it whenever a Focus is on, unless
    /// the user chose Always). Only a hint: used when the switch itself has no value.
    static func focusShowsInMenuBar() -> Bool? {
        guard let app = AXUI.app(controlCenterApp) else { return nil }
        return item(focusItem, in: app) != nil
    }

    static func toggleDoNotDisturb() async -> DeckSwitchResult {
        guard AXIsProcessTrusted() else { return .failed(AXUI.permissionHint) }
        guard let app = AXUI.app(controlCenterApp) else { return .failed("Control Center is not running") }
        // The Focus menu holds the same switches and opens smaller; Control Center otherwise.
        let openers = [focusItem, controlCenterItem].compactMap { item($0, in: app) }
        guard !openers.isEmpty else { return .failed("Control Center is not in the menu bar") }
        let before = focusShowsInMenuBar()
        for opener in openers {
            guard AXUI.press(opener) else { continue }
            let result = await pressDoNotDisturb(in: app, before: before)
            await close(app, opener: opener)
            if let result { return result }
        }
        return .failed("Could not find Do Not Disturb in Control Center")
    }

    /// With the panel open: finds the switch (opening the Focus tile if needed) and presses it.
    /// nil when it is not in this panel.
    private static func pressDoNotDisturb(in app: AXUIElement, before: Bool?) async -> DeckSwitchResult? {
        var target = await waitFor(app, seconds: 1.2) { isDoNotDisturbSwitch(AXUI.identifier($0)) }
        if target == nil, let tile = AXUI.windows(app).lazy.compactMap({ w in
            AXUI.first(in: w) { isFocusTile(AXUI.identifier($0)) }
        }).first {
            // The Focus tile opens its list of Focus modes.
            AXUI.press(tile)
            target = await waitFor(app, seconds: 1.2) { isDoNotDisturbSwitch(AXUI.identifier($0)) }
        }
        guard let target else { return nil }
        let value = AXUI.int(target, kAXValueAttribute)
        guard AXUI.press(target) else { return .failed("Could not switch Do Not Disturb") }
        if let value { return value == 0 ? .on : .off }
        if let before { return before ? .off : .on }
        return .changed
    }

    static func openNotificationCenter() -> Bool {
        guard AXIsProcessTrusted(), let app = AXUI.app(controlCenterApp), let clock = item(clockItem, in: app) else {
            return false
        }
        return AXUI.press(clock)
    }

    /// Polls Control Center's open windows for a matching element.
    private static func waitFor(_ app: AXUIElement, seconds: Double,
                                _ match: @escaping (AXUIElement) -> Bool) async -> AXUIElement? {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            for w in AXUI.windows(app) {
                if let found = AXUI.first(in: w, maxDepth: 14, where: match) { return found }
            }
            try? await Task.sleep(for: .milliseconds(60))
        } while Date() < deadline
        return nil
    }

    /// Closes the panel if it is still open (choosing a Focus can close it by itself).
    private static func close(_ app: AXUIElement, opener: AXUIElement) async {
        try? await Task.sleep(for: .milliseconds(250))
        if !AXUI.windows(app).isEmpty { AXUI.press(opener) }
    }
}

extension AXUI {
    /// An app's open windows (Control Center's panels are windows while they show).
    static func windows(_ app: AXUIElement) -> [AXUIElement] { elements(app, kAXWindowsAttribute) }
}

// MARK: - Night Shift

/// Night Shift through CoreBrightness's `CBBlueLightClient`, the private class System Settings
/// uses. Loaded at run time and checked before every use; nil when this Mac does not have it.
@MainActor
enum NightShift {
    /// `getBlueLightStatus:` fills this C struct: active, enabled, sunSchedulePermitted (BOOLs),
    /// mode (int), schedule (four ints), disableFlags (uint64), available (BOOL). `enabled` is
    /// whether Night Shift is on right now.
    nonisolated static let enabledOffset = 1
    /// Bigger than the struct (40 bytes), so a slightly larger one never writes past the buffer.
    nonisolated static let statusSize = 128

    private typealias GetStatus = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
    private typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool) -> Bool

    private static let client: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        let supports = NSSelectorFromString("supportsBlueLightReduction")
        if let m = class_getClassMethod(cls, supports) {
            typealias Supports = @convention(c) (AnyClass, Selector) -> Bool
            guard unsafeBitCast(method_getImplementation(m), to: Supports.self)(cls, supports) else { return nil }
        }
        let c = cls.init()
        guard c.responds(to: NSSelectorFromString("getBlueLightStatus:")),
              c.responds(to: NSSelectorFromString("setEnabled:")) else { return nil }
        return c
    }()

    static func isOn() -> Bool? {
        guard let client else { return nil }
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard let imp = class_getMethodImplementation(type(of: client), sel) else { return nil }
        let get = unsafeBitCast(imp, to: GetStatus.self)
        var buffer = [UInt8](repeating: 0, count: statusSize)
        let ok = buffer.withUnsafeMutableBytes { get(client, sel, $0.baseAddress!) }
        return ok ? buffer[enabledOffset] != 0 : nil
    }

    static func toggle() -> DeckSwitchResult {
        guard let client, let on = isOn() else { return .failed("Night Shift is not available on this Mac") }
        let sel = NSSelectorFromString("setEnabled:")
        guard let imp = class_getMethodImplementation(type(of: client), sel) else { return .failed("Night Shift is not available on this Mac") }
        _ = unsafeBitCast(imp, to: SetEnabled.self)(client, sel, !on)
        guard let now = isOn(), now != on else { return .failed("Night Shift did not change") }
        return now ? .on : .off
    }
}

// MARK: - Keep awake

/// Keeps the display (and so the Mac) awake with a power assertion Glasspad holds, like
/// `caffeinate -d`. Released when tapped again or when Glasspad quits.
@MainActor
final class KeepAwake {
    static let shared = KeepAwake()
    private var assertion: IOPMAssertionID?

    var isOn: Bool { assertion != nil }

    func toggle() -> DeckSwitchResult {
        if let id = assertion {
            IOPMAssertionRelease(id)
            assertion = nil
            return .off
        }
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Glasspad Keep Awake" as CFString, &id)
        guard status == kIOReturnSuccess else { return .failed("Could not keep the Mac awake") }
        assertion = id
        return .on
    }
}

// MARK: - Lock and appearance

@MainActor
enum MacSystem {
    private typealias LockFn = @convention(c) () -> Int32
    private typealias GetThemeFn = @convention(c) () -> Bool
    private typealias SetThemeFn = @convention(c) (Bool) -> Void

    private static func symbol(_ path: String, _ name: String) -> UnsafeMutableRawPointer? {
        guard let h = dlopen(path, RTLD_LAZY) else { return nil }
        return dlsym(h, name)
    }

    /// Locks the screen at once, the way the Lock Screen menu item does (login framework,
    /// private). False when it is missing, so the caller can fall back to the shortcut.
    static func lockScreen() -> Bool {
        guard let sym = symbol("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
                               "SACLockScreenImmediate") else { return false }
        return unsafeBitCast(sym, to: LockFn.self)() == 0
    }

    private static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    /// Dark mode on or off, read from the window server (private SkyLight, no permission).
    static func isDark() -> Bool? {
        guard let get = symbol(skyLight, "SLSGetAppearanceThemeLegacy") else { return nil }
        return unsafeBitCast(get, to: GetThemeFn.self)()
    }

    /// Switches light and dark the way System Settings does, without the Automation prompt.
    /// Returns the new state, or nil when SkyLight is missing or ignored the change.
    static func toggleDarkMode() -> Bool? {
        guard let dark = isDark(), let set = symbol(skyLight, "SLSSetAppearanceThemeLegacy") else { return nil }
        unsafeBitCast(set, to: SetThemeFn.self)(!dark)
        guard let now = isDark(), now != dark else { return nil }
        return now
    }
}
