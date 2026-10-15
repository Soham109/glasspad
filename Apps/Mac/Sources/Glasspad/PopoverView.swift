import GlasspadKit
import GlasspadMacCore
import SwiftUI

/// The menu bar window: who is connected and how well, anything that needs fixing, pairing,
/// two quick switches, then Settings and Quit. Diagnostics live in Settings > Advanced.
struct PopoverView: View {
    @EnvironmentObject private var model: AppModel

    static let width: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusHeader()
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            RecordingRow(macros: model.macros)

            if !model.missingPermissions.isEmpty {
                PopoverDivider()
                PermissionChecklist()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            PopoverDivider()
            PairingSection()
                .padding(.horizontal, 6)
                .padding(.vertical, 6)

            PopoverDivider()
            QuickToggles()
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

            PopoverDivider()
            FooterButtons()
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .frame(width: Self.width)
        .onAppear { model.actions.refresh() }
    }
}

private struct PopoverDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 14)
    }
}

// MARK: - Status

private struct StatusHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(model.isConnected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(model.isConnected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let signal = model.signal {
                SignalBars(quality: signal)
                    .help("\(signal.title) signal")
                    .accessibilityHidden(true)
            } else if model.link == .connecting || (model.link == .searching && !model.phones.isEmpty && !model.isPaused) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(model.statusDetail)")
    }

    private var title: String {
        if model.isConnected, let name = model.connectedPhoneName { return name }
        return model.statusTitle
    }

    private var symbol: String {
        if model.isPaused { return "pause.fill" }
        switch model.link {
        case .connected: return "iphone"
        case .failed: return "exclamationmark.triangle"
        default: return "iphone.slash"
        }
    }
}

// MARK: - Permissions

private struct PermissionChecklist: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Finish Setting Up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.missingPermissions) { item in
                PermissionRow(item: item)
            }
        }
    }
}

private struct PermissionRow: View {
    @EnvironmentObject private var model: AppModel
    let item: MissingPermission

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingsIcon(symbol: symbol, color: color, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button("Allow…", action: fix)
                .controlSize(.small)
                .accessibilityLabel("Allow \(title)")
                .accessibilityHint(hint)
        }
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch item {
        case .accessibility: "hand.raised.fill"
        case .automation: "music.note"
        }
    }

    private var color: Color {
        switch item {
        case .accessibility: .blue
        case .automation: .pink
        }
    }

    private var title: String {
        switch item {
        case .accessibility: "Accessibility"
        case .automation(let app): "\(app) Control"
        }
    }

    private var detail: String {
        switch item {
        case .accessibility: "Lets your iPhone move the pointer and click."
        case .automation(let app): "Shows what \(app) is playing on your iPhone."
        }
    }

    private var hint: String {
        switch item {
        case .accessibility: "Opens Privacy and Security, Accessibility in System Settings"
        case .automation: "Opens Privacy and Security, Automation in System Settings"
        }
    }

    private func fix() {
        switch item {
        case .accessibility: model.actions.requestAccessibility()
        case .automation: model.actions.openAutomationSettings()
        }
    }
}

// MARK: - Pairing

private struct PairingSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let url = model.pairingURL {
            VStack(spacing: 12) {
                QRCodeView(url: url, size: 216)
                Text("In Glasspad on your iPhone, tap Pair and point the camera at this code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Cancel") { model.actions.cancelPairing() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        } else {
            Button {
                model.actions.beginPairing()
            } label: {
                PopoverRow(symbol: "qrcode", title: model.phones.isEmpty ? "Pair Your iPhone…" : "Pair New iPhone…")
            }
            .buttonStyle(PopoverRowButtonStyle())
            .disabled(model.isPaused)
        }
    }
}

// MARK: - Quick toggles

private struct QuickToggles: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            ToggleRow(title: "Hide Mac Dock", symbol: "dock.rectangle",
                      isOn: Binding(get: { model.dock.hidden }, set: { model.actions.setDockHidden($0) }),
                      help: "Glasspad saves your Dock settings first and puts them back when you turn this off or quit.")
            ToggleRow(title: "Pause Glasspad", symbol: "pause.circle",
                      isOn: Binding(get: { model.isPaused }, set: { model.actions.setPaused($0) }),
                      help: "Stops listening for your iPhone until you turn this off.")
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        PopoverRow(symbol: symbol, title: title) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .help(help)
    }
}

/// Symbol column, title, then anything trailing. Every row in the popover lines up on it.
private struct PopoverRow<Trailing: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension PopoverRow where Trailing == EmptyView {
    init(symbol: String, title: String) {
        self.init(symbol: symbol, title: title) { EmptyView() }
    }
}

// MARK: - Footer

private struct FooterButtons: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsLink {
                PopoverRow(symbol: "gearshape", title: "Settings…") {
                    Text("⌘,").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(PopoverRowButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            .keyboardShortcut(",")
            Button {
                model.actions.quit()
            } label: {
                PopoverRow(symbol: "power", title: "Quit Glasspad") {
                    Text("⌘Q").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(PopoverRowButtonStyle())
            .keyboardShortcut("q")
        }
    }
}

// MARK: - Recording

/// While a macro is being recorded: says so, with Stop.
private struct RecordingRow: View {
    @ObservedObject var macros: MacroCoordinator

    var body: some View {
        if macros.isRecording {
            PopoverDivider()
            HStack(spacing: 10) {
                Image(systemName: "record.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recording a Macro")
                        .font(.body.weight(.medium))
                    Text("Press ⌃⌥⌘. to stop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop") { macros.stopRecording(fromMacMenu: true) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityElement(children: .contain)
        }
    }
}
