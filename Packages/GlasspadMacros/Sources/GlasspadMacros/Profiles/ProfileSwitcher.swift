import Foundation
import AppKit

/// Reports frontmost app changes.
public protocol FrontmostAppObserving: AnyObject, Sendable {
    func currentBundleID() -> String?
    func start(_ onChange: @escaping @Sendable (String?) -> Void)
    func stop()
}

/// Real observer: NSWorkspace's app-activation notification.
public final class WorkspaceFrontmostAppObserver: FrontmostAppObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol?

    public init() {}

    public func currentBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public func start(_ onChange: @escaping @Sendable (String?) -> Void) {
        lock.lock(); defer { lock.unlock() }
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            onChange(app?.bundleIdentifier)
        }
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = nil
    }
}

/// Follows the frontmost app and publishes which profile is active.
///
/// Apps in `ignoredBundleIDs` (Glasspad itself, by default) never switch the
/// profile, so opening Glasspad's menu does not swap the phone's buttons.
public final class ProfileSwitcher: @unchecked Sendable {
    private let observer: any FrontmostAppObserving
    private let lock = NSLock()
    private var profiles: [ContextProfile]
    private var lastBundleID: String?
    private var active: ContextProfile?
    private var handler: (@Sendable (ContextProfile?) -> Void)?
    public let ignoredBundleIDs: Set<String>

    public init(observer: any FrontmostAppObserving = WorkspaceFrontmostAppObserver(),
                profiles: [ContextProfile] = [],
                ignoredBundleIDs: Set<String> = Set([Bundle.main.bundleIdentifier].compactMap { $0 })) {
        self.observer = observer
        self.profiles = profiles
        self.ignoredBundleIDs = ignoredBundleIDs
    }

    public var activeProfile: ContextProfile? {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    public var frontmostBundleID: String? {
        lock.lock(); defer { lock.unlock() }
        return lastBundleID
    }

    /// Starts following the frontmost app. `onChange` is called with the
    /// initial profile, then whenever the active profile changes.
    public func start(onChange: @escaping @Sendable (ContextProfile?) -> Void) {
        lock.lock()
        handler = onChange
        lock.unlock()
        // If Glasspad itself is frontmost at launch, start on the fallback profile.
        let current = observer.currentBundleID().flatMap { ignoredBundleIDs.contains($0) ? nil : $0 }
        appChanged(current, force: true, ignoreFilter: true)
        observer.start { [weak self] id in self?.appChanged(id, force: false) }
    }

    public func stop() {
        observer.stop()
        lock.lock(); handler = nil; lock.unlock()
    }

    /// Replace the profile list (after the user edits one); re-resolves at once.
    public func update(profiles: [ContextProfile]) {
        lock.lock()
        self.profiles = profiles
        let id = lastBundleID
        lock.unlock()
        appChanged(id, force: false, ignoreFilter: true)
    }

    private func appChanged(_ bundleID: String?, force: Bool, ignoreFilter: Bool = false) {
        lock.lock()
        if !ignoreFilter, let bundleID, ignoredBundleIDs.contains(bundleID) {
            lock.unlock()
            return
        }
        lastBundleID = bundleID
        let next = ProfileResolver.resolve(bundleID: bundleID, in: profiles)
        let changed = force || next != active
        active = next
        let callback = handler
        lock.unlock()
        if changed { callback?(next) }
    }
}
