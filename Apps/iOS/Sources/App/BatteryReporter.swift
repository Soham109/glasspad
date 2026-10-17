import GlasspadKit
import SwiftUI
import UIKit

/// `UIDevice` battery monitoring is one switch for the whole app. StandBy and the battery
/// reporter each hold it while they need it, so neither turns it off under the other.
@MainActor
enum BatteryMonitoring {
    private static var holders = 0

    static func acquire() {
        holders += 1
        if holders == 1 { UIDevice.current.isBatteryMonitoringEnabled = true }
    }

    static func release() {
        guard holders > 0 else { return }
        holders -= 1
        if holders == 0 { UIDevice.current.isBatteryMonitoringEnabled = false }
    }
}

/// Tells the Mac the iPhone's battery (it shows it on the iPhone's row). Low battery on the
/// phone is left to iOS's own alert. Watches the battery only while connected and in front;
/// nothing runs otherwise.
@MainActor
@Observable
final class BatteryReporter {
    static let shared = BatteryReporter()

    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var watching = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// What this session's Mac was last told; nil until told.
    @ObservationIgnored private var sent: PhoneStatus?
    @ObservationIgnored private var tracking = false
    #if DEBUG
    @ObservationIgnored private var demoPercent: Int?
    #endif

    /// The app came to the front or went to the background.
    func setForeground(_ active: Bool) {
        foreground = active
        if !tracking {
            tracking = true
            #if DEBUG
            applyDemo()
            #endif
            trackConnection()
        }
        update()
    }

    /// Follows `MacSession.isConnected` without touching the session itself.
    private func trackConnection() {
        withObservationTracking {
            _ = MacSession.shared.isConnected
        } onChange: {
            Task { @MainActor in
                BatteryReporter.shared.update()
                BatteryReporter.shared.trackConnection()
            }
        }
    }

    private func update() {
        let connected = MacSession.shared.isConnected
        if !connected { sent = nil }
        let wanted = connected && foreground
        guard wanted != watching else { return }
        watching = wanted
        if wanted {
            BatteryMonitoring.acquire()
            let center = NotificationCenter.default
            observers = [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification].map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { BatteryReporter.shared.refresh() }
                }
            }
            refresh()
            // The first reading can come a moment after monitoring starts.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if self.watching && self.sent == nil { self.refresh() }
            }
        } else {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            BatteryMonitoring.release()
        }
    }

    /// A new reading: tell the Mac when it changed.
    private func refresh() {
        let device = UIDevice.current
        var status = PhoneStatus(batteryLevel: device.batteryLevel,
                                 charging: device.batteryState == .charging || device.batteryState == .full)
        #if DEBUG
        if let demoPercent { status = PhoneStatus(batteryPercent: demoPercent, charging: false) }
        #endif
        guard status.batteryPercent != nil else { return }
        if status != sent {
            sent = status
            MacSession.shared.send(control: .phoneStatus(status))
        }
    }

    #if DEBUG
    /// `-GPBattery <percent>`: pretend to run on battery at that level, for screenshots.
    private func applyDemo() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-GPBattery"), i + 1 < args.count, let percent = Int(args[i + 1]) else { return }
        demoPercent = min(100, max(0, percent))
    }
    #endif
}
