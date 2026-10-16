import Foundation
import GlasspadKit
import Observation

/// The phone's heat and Low Power Mode as a `PowerPolicy`, kept current. Views read `policy`
/// (observed); the session and the router get `onChange` callbacks.
@MainActor
@Observable
final class PowerMonitor {
    static let shared = PowerMonitor()

    private(set) var policy: PowerPolicy
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var listeners: [@MainActor (PowerPolicy) -> Void] = []

    private init() {
        policy = Self.read()
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PowerMonitor.shared.refresh() }
            })
        }
    }

    /// Calls `body` now and after every change.
    func onChange(_ body: @escaping @MainActor (PowerPolicy) -> Void) {
        listeners.append(body)
        body(policy)
    }

    private func refresh() {
        let fresh = Self.read()
        guard fresh != policy else { return }
        policy = fresh
        GPLog.log("power: heat \(fresh.heat), low power \(fresh.lowPower)")
        for listener in listeners { listener(fresh) }
    }

    private static func read() -> PowerPolicy {
        let info = ProcessInfo.processInfo
        return PowerPolicy(heat: heat(info.thermalState), lowPower: info.isLowPowerModeEnabled)
    }

    /// iOS's thermal state as the one heat model (StandBy reads it too).
    nonisolated static func heat(_ state: ProcessInfo.ThermalState) -> PowerPolicy.Heat {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }
}
