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

/// Tells the Mac the iPhone's battery (it shows it on the iPhone's row), and says so on the
/// phone at 20% and 10%, since Glasspad hides the status bar. Watches the battery only while
/// connected and in front; nothing runs otherwise.
@MainActor
@Observable
final class BatteryReporter {
    static let shared = BatteryReporter()

    /// The low battery notice to show, cleared after a few seconds.
    private(set) var notice: LowBatteryNotice?

    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var watching = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// What this session's Mac was last told; nil until told.
    @ObservationIgnored private var sent: PhoneStatus?
    @ObservationIgnored private var low = LowBatteryWatch()
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

    /// A new reading: tell the Mac when it changed, and say so here when it runs low.
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
        let due = low.update(percent: status.batteryPercent, charging: status.charging ?? false)
        // StandBy shows the charge itself.
        if let due, StandByMonitor.shared.visibleCount == 0 { show(due) }
    }

    private func show(_ percent: Int) {
        let shown = LowBatteryNotice(percent: percent)
        notice = shown
        UIAccessibility.post(notification: .announcement, argument: "iPhone battery is at \(percent)%.")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if self.notice == shown { self.notice = nil }
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

struct LowBatteryNotice: Equatable {
    let id = UUID()
    let percent: Int
}

/// "iPhone battery is at 20%.": a quiet capsule at the bottom, like the warm notice. It never
/// takes touches and leaves after a few seconds.
struct BatteryNotice: View {
    @Environment(\.palette) private var palette
    var reporter = BatteryReporter.shared

    var body: some View {
        VStack {
            Spacer()
            if let notice = reporter.notice {
                Label("iPhone battery is at \(notice.percent)%.",
                      systemImage: PhoneBattery(percent: notice.percent, charging: false).symbol)
                    .font(.footnote)
                    .foregroundStyle(palette.inkColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassCapsule()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .transition(.opacity)
                    .id(notice.id)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: reporter.notice)
    }
}
