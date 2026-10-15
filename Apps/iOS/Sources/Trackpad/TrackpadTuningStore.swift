import Foundation
import GlasspadKit
import Observation

/// The phone's own trackpad feel settings (`TrackpadTuning`): pointer speed on top of the Mac's
/// tracking speed, acceleration, scroll speed, momentum and per-kind haptic strength. Stored on
/// the phone, applied by the local recognizer and haptics, and sent to the Mac inside
/// `ControlMessage.settings` so the Mac's recognizer uses the same values.
@MainActor
@Observable
final class TrackpadTuningStore {
    static let shared = TrackpadTuningStore()

    var tuning: TrackpadTuning {
        didSet {
            guard tuning != oldValue else { return }
            if let data = try? JSONEncoder().encode(tuning) { defaults.set(data, forKey: Self.key) }
            Haptics.shared.tuning = tuning
            sendToMac()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastSent: (tuning: TrackpadTuning, at: TimeInterval)?
    private static let key = "trackpadTuning"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let t = try? JSONDecoder().decode(TrackpadTuning.self, from: data) {
            tuning = t.clamped
        } else {
            tuning = .default
        }
        Haptics.shared.tuning = tuning
    }

    /// The Mac's settings with this phone's tuning in place.
    func merged(_ mac: TrackpadSettings) -> TrackpadSettings {
        var s = mac
        s.tuning = tuning
        return s
    }

    /// Sends the tuning to the Mac (it keeps it and sends the merged settings back).
    func sendToMac() {
        let session = MacSession.shared
        guard session.isConnected else { return }
        lastSent = (tuning, ProcessInfo.processInfo.systemUptime)
        session.send(control: .settings(merged(session.trackpadSettings)))
    }

    /// Called whenever settings arrive from the Mac: if the Mac's copy of the tuning differs
    /// (a fresh Mac, or a change made while disconnected), send ours.
    func macSettingsArrived(_ mac: TrackpadSettings) {
        guard mac.tuning != tuning else { return }
        // The Mac echoes the merged settings back; do not resend while that echo is in flight.
        let now = ProcessInfo.processInfo.systemUptime
        if let l = lastSent, l.tuning == tuning, now - l.at < 2 { return }
        sendToMac()
    }
}
