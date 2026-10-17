import AppKit
import CoreGraphics
import Foundation

/// Watches for the two moments the phone should hear about: the Mac about to sleep, and its
/// screen locking or unlocking. The phone can then say "asleep" or "locked" instead of a
/// generic "Looking for your Mac". The notification centers are injected, so tests post fake
/// notifications and never touch the real ones.
@MainActor
public final class MacPresence {
    /// The screen is locked now.
    public private(set) var screenLocked: Bool
    /// The Mac is about to sleep (`NSWorkspace.willSleepNotification`).
    public var onSleep: (() -> Void)?
    /// The screen locked (true) or unlocked (false). Only real changes are reported.
    public var onLockChange: ((Bool) -> Void)?

    /// What macOS posts on the distributed center when the screen locks and unlocks.
    public static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    public static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    private let workspace: NotificationCenter
    private let distributed: NotificationCenter
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// `initiallyLocked` is read once at start (Glasspad can start behind a locked screen).
    public init(workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
                distributed: NotificationCenter = DistributedNotificationCenter.default(),
                initiallyLocked: Bool = MacPresence.isScreenLockedNow()) {
        self.workspace = workspace
        self.distributed = distributed
        self.screenLocked = initiallyLocked
    }

    public func start() {
        guard observers.isEmpty else { return }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.onSleep?() }
        observe(distributed, Self.screenLocked) { $0.setLocked(true) }
        observe(distributed, Self.screenUnlocked) { $0.setLocked(false) }
    }

    public func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (MacPresence) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    private func setLocked(_ locked: Bool) {
        guard locked != screenLocked else { return }
        screenLocked = locked
        onLockChange?(locked)
    }

    /// The login session's own flag (a quick read from the window server, no waiting).
    public nonisolated static func isScreenLockedNow() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
