import GlasspadKit
import GlasspadMacCore
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var controller: GlasspadController
    @StateObject private var login = LaunchAtLogin()
    @State private var showGestures = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusHeader()
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            RecordingRow(macros: controller.macros)

            if !controller.accessibilityTrusted {
                Divider()
                AccessibilityRow()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            Divider()
            PairingSection()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            if !controller.phones.isEmpty {
                Divider()
                PhonesSection()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            Divider()
            DisclosureGroup(isExpanded: $showGestures) {
                GestureList()
                    .padding(.top, 6)
            } label: {
                Text("Gestures")
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch at Login", isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                HStack {
                    SettingsLink {
                        Text("Settings…")
                    }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                    .keyboardShortcut(",")
                    Spacer()
                    Button("Quit Glasspad") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .onAppear {
            controller.refreshAccessibility()
            login.refresh()
        }
    }
}

private struct StatusHeader: View {
    @EnvironmentObject private var controller: GlasspadController

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: controller.linkState.symbol)
                .font(.title2)
                .foregroundStyle(controller.linkState.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: controller.linkState == .searching)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.connectedPhoneName ?? "Glasspad")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let rtt = formatRTT(controller.stats.rttMedianMs), controller.linkState.isConnected {
                Text(rtt)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Median round trip time. 95th percentile: \(formatRTT(controller.stats.rttP95Ms) ?? "n/a")")
                    .accessibilityLabel("Round trip \(rtt)")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if case .failed(let reason) = controller.linkState { return reason }
        if let error = controller.lastError { return error }
        return controller.linkState.title
    }
}

private struct AccessibilityRow: View {
    @EnvironmentObject private var controller: GlasspadController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility Access")
                    .font(.headline)
                Text("Needed to move the pointer and click.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open…") {
                controller.requestAccessibility()
                SystemSettings.openAccessibility()
            }
            .controlSize(.small)
            .accessibilityHint("Opens Privacy and Security, Accessibility in System Settings")
        }
    }
}

private struct PairingSection: View {
    @EnvironmentObject private var controller: GlasspadController

    var body: some View {
        if let url = controller.pairingURL {
            VStack(spacing: 10) {
                if let qr = QRCode.image(for: url.absoluteString, size: 180) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 180, height: 180)
                        .padding(10)
                        .background(.white, in: .rect(cornerRadius: 12))
                        .accessibilityLabel("Pairing code")
                }
                Text("Scan with the Glasspad app on your iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Cancel") { controller.cancelPairing() }
                    .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .glassBackground(cornerRadius: 16)
        } else {
            Button {
                controller.beginPairing()
            } label: {
                Label("Pair New iPhone…", systemImage: "qrcode")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct PhonesSection: View {
    @EnvironmentObject private var controller: GlasspadController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paired iPhones")
                .font(.headline)
            ForEach(controller.phones) { phone in
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(phone.phoneName)
                    if controller.connectedPhoneName == phone.phoneName, controller.linkState.isConnected {
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        controller.revoke(phone)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Revoke")
                    .accessibilityLabel("Revoke \(phone.phoneName)")
                }
            }
        }
    }
}

struct GestureList: View {
    @EnvironmentObject private var controller: GlasspadController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(controller.capabilities.summary, id: \.gesture) { item in
                HStack {
                    Text(item.gesture.displayName)
                    Spacer()
                    Text(item.mode.label)
                        .foregroundStyle(item.mode == .native ? .primary : .secondary)
                }
                .font(.callout)
                .help(item.mode.help)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// While a macro is being recorded: says so, with Stop.
private struct RecordingRow: View {
    @ObservedObject var macros: MacroCoordinator

    var body: some View {
        if macros.isRecording {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Recording a macro")
                    .font(.headline)
                Spacer()
                Button("Stop") { macros.stopRecording(fromMacMenu: true) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}
