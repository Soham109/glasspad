import Foundation
import GlasspadKit

/// Watches the trackpad preference domains and publishes `TrackpadSettings` whenever the
/// mapped result changes. Two sources, because neither alone is reliable:
/// - Distributed notifications: `SwipeScrollDirectionDidChangeNotification` (posted when
///   natural scrolling changes; used by open-source scroll tools), plus two multitouch names
///   that are guesses, not verified on macOS 26. A silent name costs nothing.
/// - Polling every 2 s, which catches every key, including the ones with no notification.
@MainActor
public final class TrackpadPrefsWatcher {
    public private(set) var settings: TrackpadSettings
    public var onChange: ((TrackpadSettings) -> Void)?

    private let pollInterval: TimeInterval
    private let read: () -> TrackpadSettings
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    static let notificationNames = [
        "SwipeScrollDirectionDidChangeNotification",
        "com.apple.AppleMultitouchTrackpad.prefsChanged",
        "com.apple.MultitouchSupport.HID.ReloadPrefs",
    ]

    public init(pollInterval: TimeInterval = 2, read: @escaping () -> TrackpadSettings = TrackpadPrefsReader.read) {
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
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
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
