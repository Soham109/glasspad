import Combine
import Foundation
import GlasspadKit

/// Keeps the Mac's own Dock out of the way while you drive the Mac from the phone.
///
/// How: save the user's com.apple.dock `autohide`, `autohide-delay` and `autohide-time-modifier`
/// (including "not set"), then turn autohide on with a 1000 s reveal delay and no animation, so
/// the Dock never slides in, and restart the Dock. Turning it off writes the saved values back
/// exactly (deleting keys that were not set) and restarts the Dock again.
///
/// The saved values are written to Glasspad's own preferences before the Dock is touched, so a
/// crash or force quit is undone on the next launch (`recoverAfterCrash`). Restored on: switch
/// off, phone disconnect (for the "while connected" option), app quit, and next launch.
@MainActor
public final class MacDockHider: ObservableObject {
    /// The one the app uses (the phone and the menu bar switch the same Dock).
    public static let shared = MacDockHider()

    public static let domain = "com.apple.dock"
    public static let keys = ["autohide", "autohide-delay", "autohide-time-modifier"]
    /// Seconds the pointer must rest at the screen edge before the Dock shows: never, in practice.
    public static let hiddenDelay = 1000.0

    /// Glasspad's own keys.
    static let savedKey = "macDockHider.saved"
    static let hideWhileConnectedKey = "macDockHider.hideWhileConnected"

    private let dock: DefaultsStore
    private let own: UserDefaults
    private let runner: ProcessRunning

    /// The manual switch. Not remembered across launches: a fresh start always shows the Dock.
    public private(set) var manual = false
    public private(set) var hideWhileConnected: Bool
    public private(set) var connected = false
    /// Called after every change (the phone is told through it).
    public var onChange: ((MacDockState) -> Void)?
    /// For the menu bar UI.
    @Published public private(set) var published = MacDockState(hidden: false, hideWhileConnected: false, isHiddenNow: false)

    public init(dock: DefaultsStore = CFPreferencesStore(), own: UserDefaults = .standard,
                runner: ProcessRunning = LiveProcessRunner()) {
        self.dock = dock
        self.own = own
        self.runner = runner
        hideWhileConnected = own.bool(forKey: Self.hideWhileConnectedKey)
        published = state
    }

    public var isHidden: Bool { own.dictionary(forKey: Self.savedKey) != nil }
    public var state: MacDockState {
        MacDockState(hidden: manual, hideWhileConnected: hideWhileConnected, isHiddenNow: isHidden)
    }

    // MARK: Inputs

    /// Call once at launch: if the last run died while the Dock was hidden, put it back.
    public func recoverAfterCrash() {
        if isHidden {
            GPLog.log("mac dock: restoring values saved by a run that did not quit cleanly")
            restore()
        }
        published = state
    }

    public func setManual(_ on: Bool) {
        manual = on
        apply()
    }

    public func setHideWhileConnected(_ on: Bool) {
        hideWhileConnected = on
        own.set(on, forKey: Self.hideWhileConnectedKey)
        apply()
    }

    public func setConnected(_ on: Bool) {
        guard connected != on else { return }
        connected = on
        apply()
    }

    /// Both switches from the phone.
    public func set(_ s: MacDockState) {
        manual = s.hidden
        hideWhileConnected = s.hideWhileConnected
        own.set(s.hideWhileConnected, forKey: Self.hideWhileConnectedKey)
        apply()
    }

    /// App is quitting: always put the Dock back.
    public func appWillTerminate() {
        if isHidden { restore() }
        published = state
    }

    // MARK: Core

    public var wantsHidden: Bool { manual || (hideWhileConnected && connected) }

    private func apply() {
        if wantsHidden && !isHidden {
            hide()
        } else if !wantsHidden && isHidden {
            restore()
        }
        published = state
        onChange?(state)
    }

    private func hide() {
        var saved: [String: Any] = [:]
        for key in Self.keys {
            if let v = dock.value(forKey: key, domain: Self.domain) { saved[key] = v }
        }
        // Remember "what was there" first, including the absent keys (an empty dictionary is
        // still a saved state), so a crash after this line is still undone.
        own.set(saved, forKey: Self.savedKey)
        dock.set(true, forKey: "autohide", domain: Self.domain)
        dock.set(Self.hiddenDelay, forKey: "autohide-delay", domain: Self.domain)
        dock.set(0.0, forKey: "autohide-time-modifier", domain: Self.domain)
        dock.synchronize(domain: Self.domain)
        restartDock()
        GPLog.log("mac dock: hidden (saved \(saved))")
    }

    private func restore() {
        let saved = own.dictionary(forKey: Self.savedKey) ?? [:]
        for key in Self.keys {
            dock.set(saved[key], forKey: key, domain: Self.domain)
        }
        dock.synchronize(domain: Self.domain)
        own.removeObject(forKey: Self.savedKey)
        restartDock()
        GPLog.log("mac dock: restored \(saved)")
    }

    private func restartDock() {
        // The Dock reads these keys at start; launchd restarts it at once.
        _ = runner.run("/usr/bin/killall", ["Dock"])
    }
}

/// Another app's preferences, injectable so tests never touch the real Dock.
public protocol DefaultsStore: AnyObject {
    func value(forKey key: String, domain: String) -> Any?
    /// nil deletes the key.
    func set(_ value: Any?, forKey key: String, domain: String)
    func synchronize(domain: String)
}

/// CFPreferences for the current user, any host.
public final class CFPreferencesStore: DefaultsStore {
    public init() {}
    public func value(forKey key: String, domain: String) -> Any? {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }
    public func set(_ value: Any?, forKey key: String, domain: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, domain as CFString)
    }
    public func synchronize(domain: String) { CFPreferencesAppSynchronize(domain as CFString) }
}

/// Runs a command line tool and waits for it (short tools only).
public protocol ProcessRunning: AnyObject {
    @discardableResult func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String)
}

public final class LiveProcessRunner: ProcessRunning {
    public init() {}
    @discardableResult
    public func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
    }
}
