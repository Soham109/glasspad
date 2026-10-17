import Foundation
import GlasspadKit

/// Watches the trackpad preference domains and publishes `TrackpadSettings` whenever the
/// mapped result changes. Two sources, because neither alone is reliable:
/// - Distributed notifications: `SwipeScrollDirectionDidChangeNotification` (posted when
///   natural scrolling changes; used by open-source scroll tools), plus two multitouch names
///   that are guesses, not verified on macOS 26. A silent name costs nothing.
/// - Polling every 2 s while a phone is connected, which catches every key, including the
///   ones with no notification. With no phone it does not poll at all (nobody is waiting for
///   the settings, and an idle Mac should not wake for them); it reads again the moment a
///   phone connects.
@MainActor
public final class TrackpadPrefsWatcher {
    public private(set) var settings: TrackpadSettings
    public var onChange: ((TrackpadSettings) -> Void)?

    private let pollInterval: TimeInterval
    private var phoneConnected = false
    private var started = false
    /// Seconds between reads now; nil while no phone is connected (no polling).
    public var currentInterval: TimeInterval? { phoneConnected ? pollInterval : nil }
    private let read: () -> TrackpadSettings
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    static let notificationNames = [
        "SwipeScrollDirectionDidChangeNotification",
        "com.apple.AppleMultitouchTrackpad.prefsChanged",
        "com.apple.MultitouchSupport.HID.ReloadPrefs",
    ]

    public init(pollInterval: TimeInterval = 2,
                read: @escaping () -> TrackpadSettings = TrackpadPrefsReader.read) {
        self.pollInterval = pollInterval
        self.read = read
        self.settings = read()
    }

    public func start() {
        stop()
        let center = DistributedNotificationCenter.default()
        for name in Self.notificationNames {
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(token)
        }
        started = true
        schedule()
    }

    /// A phone connected or left. Connected, it reads at once and then every `pollInterval`.
    public func setPhoneConnected(_ connected: Bool) {
        guard connected != phoneConnected else { return }
        phoneConnected = connected
        if connected { refresh() }
        if started { schedule() }
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard let interval = currentInterval else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The repeating read's interval while started (tests).
    var scheduledInterval: TimeInterval? { timer?.timeInterval }

    public func stop() {
        started = false
        timer?.invalidate()
        timer = nil
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    /// Re-reads the domains; calls `onChange` only when the mapped settings differ.
    public func refresh() {
        let fresh = read()
        guard fresh != settings else { return }
        settings = fresh
        onChange?(fresh)
    }
}
