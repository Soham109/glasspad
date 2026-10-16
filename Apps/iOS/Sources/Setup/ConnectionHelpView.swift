import GlasspadKit
import SwiftUI

/// Plain words for link failures and quality.
enum ConnectionWords {
    /// A failure reason from the transport, said the way a person would.
    static func failure(_ reason: String) -> String {
        let r = reason.lowercased()
        if reason == GlasspadService.replacedFailure { return "Another iPhone is using this Mac. A Mac follows one iPhone at a time." }
        if r.contains("not paired") || r.contains("key confirmation") {
            return "This Mac no longer has this iPhone's key. Pair again: on the Mac, choose Pair Your iPhone."
        }
        if r.contains("wrong mac") { return "A different Mac answered. Pair again with the one you want." }
        if r.contains("unsupported version") { return "The Glasspad on your Mac is a different version. Update both to the same version." }
        if r.contains("handshake timeout") || r.contains("unreachable") || r.contains("timed out") {
            return "Your Mac was found but did not answer. A guest or office Wi-Fi, a VPN or a firewall on the Mac can block it."
        }
        return reason
    }

    @MainActor static var blockedNetwork: String { "\(MacSession.shared.macName ?? "Your Mac") was found, but this network does not let devices talk to each other. Guest, hotel and office Wi-Fi often do this, and so can a VPN on this iPhone or a firewall on the Mac. Try your home Wi-Fi, or turn the VPN off." }

    static let localNetworkOff = "iOS is blocking Glasspad from your Wi-Fi. In Settings, open Glasspad and turn on Local Network."
}

/// Settings > Connection: the current Mac, the link in words, and what to check when it will
/// not connect.
struct ConnectionHelpView: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared
    var probe = LocalNetworkProbe.shared
    var network = PhoneNetwork.shared
    var store = PairingStore.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Form {
                macSection
                // The checks only matter while it is not connected.
                if !session.isConnected {
                    phoneSection
                    checklistSection
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            probe.start()
            network.start()
            session.setDiagnosticsVisible(true)
        }
        .onDisappear {
            probe.stop()
            network.stop()
            session.setDiagnosticsVisible(false)
        }
    }

    // MARK: Mac

    private var macName: String { session.macName ?? "Your Mac" }

    @ViewBuilder private var macSection: some View {
        Section {
            if store.selected == nil {
                Text("No Mac paired yet.").foregroundStyle(palette.inkSoftColor)
            } else {
                LabeledContent("Mac", value: macName)
                LabeledContent {
                    HStack(spacing: 6) {
                        ConnectionDot(state: session.state)
                        Text(stateWords)
                    }
                } label: {
                    Text("Status")
                }
                .accessibilityElement(children: .combine)
                if session.isConnected {
                    LabeledContent("Quality", value: LinkQuality(session.roundTrip)?.title ?? "Checking")
                    if session.linkPath == .peerToPeer {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Network", value: LinkPath.peerToPeer.title)
                            Text("Your Mac is not on this Wi-Fi, so the two talk directly. Joining the same Wi-Fi is smoother.")
                                .font(.footnote).foregroundStyle(palette.inkSoftColor)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    LabeledContent("Accessibility", value: accessibilityWords)
                    if let automation = session.macStatus?.automationMedia, automation != .notNeeded {
                        LabeledContent("Spotify and Music", value: automationWords(automation))
                    }
                }
            }
        } header: {
            Text("Mac")
        } footer: {
            if !session.isConnected, session.linkIssue == .networkBlocksDevices {
                Text(ConnectionWords.blockedNetwork)
            } else if !session.isConnected, probe.effectiveAccess == .denied {
                Text(ConnectionWords.localNetworkOff)
            } else if session.macNeedsAccessibility {
                Text(MacPermissionBanner.steps)
            }
        }
        .listRowBackground(palette.raisedColor)
    }

    private var stateWords: String {
        switch session.state {
        case .failed where session.isReplaced: "In use by another iPhone"
        case .failed: "Could not connect"
        default: session.state.statusText
        }
    }

    private var accessibilityWords: String {
        switch session.macStatus?.accessibilityTrusted {
        case true?: "On"
        case false?: "Off"
        case nil: "Not reported"
        }
    }

    private func automationWords(_ state: AutomationState) -> String {
        switch state {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not asked yet"
        case .notNeeded: "Not needed"
        }
    }

    // MARK: This iPhone

    private var phoneSection: some View {
        Section("This iPhone") {
            CheckRow(title: "Wi-Fi", value: wifiWords, ok: network.onWiFi)
            CheckRow(title: "Local Network", value: localNetworkWords, ok: localNetworkOK)
            if probe.effectiveAccess == .denied {
                Button("Open Settings") { openAppSettings() }
            }
            if store.selected != nil, !session.isConnected {
                CheckRow(title: "\(macName) on this Wi-Fi",
                         value: probe.seesSelectedMac ? "Seen" : "Not seen",
                         ok: probe.seesSelectedMac ? true : (probe.stillNotConnected(after: SetupChecklistView.searchGrace) ? false : nil))
            }
        }
        .listRowBackground(palette.raisedColor)
    }

    private var wifiWords: String {
        switch network.onWiFi {
        case true?: "On"
        case false?: "Off"
        case nil: "Checking"
        }
    }

    private var localNetworkOK: Bool? {
        switch probe.effectiveAccess {
        case .allowed: true
        case .denied: false
        case .unknown: nil
        }
    }

    private var localNetworkWords: String {
        switch probe.effectiveAccess {
        case .allowed: "Allowed"
        case .denied: "Not allowed"
        case .unknown: probe.nothingFound(after: SetupChecklistView.searchGrace) ? "Not sure" : "Checking"
        }
    }

    // MARK: Can't connect

    private var checklistSection: some View {
        Section {
            HelpRow(symbol: "wifi", title: "Same Wi-Fi",
                    detail: "Your iPhone and Mac need to be on the same Wi-Fi network. Mobile data does not reach the Mac.")
            HelpRow(symbol: "network", title: "Local Network Permission",
                    detail: "In Settings, open Glasspad and turn on Local Network. If it is off, Glasspad cannot see your Mac.")
            HelpRow(symbol: "building.2", title: "Guest or Office Wi-Fi",
                    detail: "Hotel, school, office and guest networks often stop devices from seeing each other. Try another network.")
            VStack(alignment: .leading, spacing: 10) {
                HelpRow(symbol: "moon.zzz", title: "Mac Asleep",
                        detail: "A sleeping Mac cannot answer. Wake it, or turn on Wake for network access in the Mac's Battery or Energy settings.")
                if store.selected?.wakeTarget?.lastIPv4 != nil, !session.isConnected {
                    LinkActions().frame(maxWidth: .infinity)
                }
            }
            HelpRow(symbol: "lock.shield", title: "VPN on This iPhone",
                    detail: "Some VPNs send all traffic away, including to your Mac. Turn the VPN off, or allow local network access in its settings.")
            HelpRow(symbol: "menubar.rectangle", title: "Glasspad on the Mac",
                    detail: "The Glasspad icon should be in the Mac's menu bar. If not, open Glasspad from Applications.")
            if store.selected != nil {
                Button {
                    Haptics.shared.tap()
                    session.reconnect()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Text("If It Won't Connect")
        }
        .listRowBackground(palette.raisedColor)
    }
}

/// A label, its value, and a mark when the answer is known.
private struct CheckRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let value: String
    let ok: Bool?

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(value)
                if let ok {
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(ok ? palette.good : palette.caution)
                        .accessibilityHidden(true)
                }
            }
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One thing to check, with a symbol.
private struct HelpRow: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(palette.inkSoftColor)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(palette.inkColor)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
