import Foundation
import GlasspadKit
import Network
import Observation
import UIKit

/// The first-run checklist's state: when it opens by itself, and the "move your finger" test.
///
/// The Mac does not echo motion back, so the test is honest about what it can know: touches
/// were sent while the link was up (the Mac pings every second, and the phone drops the link
/// after 3.5 s of silence) and the Mac did not report Accessibility off.
@MainActor
@Observable
final class SetupGuide {
    static let shared = SetupGuide()

    /// A Mac was just paired and the checklist was never finished: open it once the pairing
    /// screens are out of the way.
    var pendingAutoShow = false
    /// The trackpad shows the coach card and counts finger travel.
    private(set) var testActive = false
    /// Finger travel sent to the Mac during the test, in points.
    private(set) var testTravel: Double = 0
    private(set) var testPassed = false

    /// This much one-finger travel, sent while connected, passes the test.
    static let travelNeeded: Double = 180

    @ObservationIgnored private var lastPoint: [UInt8: CGPoint] = [:]

    private init() {}

    var isComplete: Bool { PhoneSettings.shared.setupComplete }

    /// The Mac says Accessibility is on, or does not report it (an older Mac build). Only a
    /// clear "off" blocks.
    var accessibilityOK: Bool { MacSession.shared.macStatus?.accessibilityTrusted != false }

    /// Called after every successful pairing.
    func paired() {
        guard !isComplete else { return }
        testPassed = false
        pendingAutoShow = true
    }

    func startTest() {
        testTravel = 0
        lastPoint = [:]
        testActive = true
        AppRouter.shared.showSetup = false
        AppRouter.shared.show(.trackpad)
    }

    func cancelTest() {
        testActive = false
    }

    /// One touch snapshot from the trackpad.
    func note(_ frame: TouchFrame) {
        guard testActive, !testPassed else { return }
        let session = MacSession.shared
        let active = frame.touches.filter { $0.phase.isActive }
        guard session.isConnected, accessibilityOK, active.count == 1, let touch = active.first else {
            lastPoint = [:]
            return
        }
        let p = CGPoint(x: touch.x, y: touch.y)
        if let last = lastPoint[touch.id] {
            testTravel += hypot(p.x - last.x, p.y - last.y)
        }
        lastPoint = [touch.id: p]
        if testTravel >= Self.travelNeeded { pass() }
    }

    private func pass() {
        testPassed = true
        Haptics.shared.play(.snap)
        UIAccessibility.post(notification: .announcement, argument: "Your touches reached your Mac.")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            self.testActive = false
            if self.accessibilityOK {
                PhoneSettings.shared.setupComplete = true
            } else {
                AppRouter.shared.showSetup = true
            }
        }
    }

    #if DEBUG
    /// Screenshots only.
    func debugSet(active: Bool, travel: Double, passed: Bool) {
        testActive = active
        testTravel = travel
        testPassed = passed
    }
    #endif
}

/// Best-effort answer to "did iOS allow Local Network access?". iOS has no API to ask, so this
/// browses for Glasspad Macs: any result (or a connection) means allowed, and a browse refused
/// with the DNS-SD "policy denied" error (-65570) means not allowed. Anything else is unknown.
@MainActor
@Observable
final class LocalNetworkProbe {
    static let shared = LocalNetworkProbe()

    enum Access: Equatable { case unknown, allowed, denied }

    private(set) var access: Access = .unknown
    /// Macs advertising Glasspad on this network right now.
    private(set) var nearby: [DiscoveredMac] = []
    /// When browsing started (for "nothing found in 5 s").
    private(set) var startedAt: Date?

    @ObservationIgnored private var discovery: GlasspadDiscovery?
    @ObservationIgnored private var users = 0

    private init() {}

    /// The selected Mac is advertising on this network.
    var seesSelectedMac: Bool {
        guard let id = PairingStore.shared.selected?.macID else { return false }
        return nearby.contains { $0.macID == id }
    }

    /// Effective answer, also counting a link that got as far as connecting (which needs it).
    var effectiveAccess: Access {
        switch MacSession.shared.state {
        case .connected, .connecting: return .allowed
        default:
            if MacSession.shared.linkIssue == .localNetworkDenied { return .denied }
            return access
        }
    }

    /// Browsed this long and still not connected to the selected Mac.
    func stillNotConnected(after seconds: TimeInterval, now: Date = Date()) -> Bool {
        guard let startedAt, !MacSession.shared.isConnected else { return false }
        return now.timeIntervalSince(startedAt) >= seconds
    }

    /// Browsed this long and found no Mac at all.
    func nothingFound(after seconds: TimeInterval, now: Date = Date()) -> Bool {
        guard let startedAt, nearby.isEmpty, !MacSession.shared.isConnected else { return false }
        return now.timeIntervalSince(startedAt) >= seconds
    }

    func start() {
        users += 1
        guard discovery == nil else { return }
        startedAt = Date()
        let d = GlasspadDiscovery()
        d.onChange = { macs in
            MainActor.assumeIsolated {
                let probe = LocalNetworkProbe.shared
                probe.nearby = macs
                if !macs.isEmpty { probe.access = .allowed }
            }
        }
        d.onFailure = { reason in
            MainActor.assumeIsolated {
                if Self.isPolicyDenied(reason) { LocalNetworkProbe.shared.access = .denied }
            }
        }
        discovery = d
        d.start()
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        discovery?.stop()
        discovery = nil
        nearby = []
        startedAt = nil
        // A denial stays known; "allowed" stays too (iOS asks only once per install).
    }

    nonisolated static func isPolicyDenied(_ reason: String) -> Bool {
        reason.contains("PolicyDenied") || reason.contains("-65570")
    }
}

/// Whether this iPhone is on Wi-Fi at all (the Mac must share a network with it).
@MainActor
@Observable
final class PhoneNetwork {
    static let shared = PhoneNetwork()

    private(set) var onWiFi: Bool?
    @ObservationIgnored private var monitor: NWPathMonitor?

    private init() {}

    func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { path in
            let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            DispatchQueue.main.async { PhoneNetwork.shared.onWiFi = wifi }
        }
        m.start(queue: DispatchQueue(label: "glasspad.phone-network"))
        monitor = m
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}

/// Opens Glasspad's page in the iPhone's Settings app (Local Network lives there).
@MainActor
func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}
