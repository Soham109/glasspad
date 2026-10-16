import GlasspadKit
import GlasspadMacCore
import SwiftUI

/// The menu bar window, laid out like the system's own menu bar extras (Wi-Fi, Bluetooth):
/// the name with an on switch, the iPhone as a device row, anything that needs fixing,
/// pairing and the Dock switch, then plain Settings and Quit rows.
struct PopoverView: View {
    @EnvironmentObject private var model: AppModel

    static let width: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderRow()
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)

            PopoverDivider()
            StatusRow()
                .padding(.horizontal, 6)
                .padding(.vertical, 5)

            RecordingRow(macros: model.macros)

            if !model.missingPermissions.isEmpty {
                PopoverDivider()
                PermissionChecklist()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }

            PopoverDivider()
            PairingSection()
                .padding(.horizontal, 6)
                .padding(.top, 5)
            DockRow()
                .padding(.horizontal, 6)
                .padding(.bottom, 5)

            PopoverDivider()
            FooterButtons()
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
        }
        .frame(width: Self.width)
        .animation(.easeInOut(duration: 0.2), value: model.isPaused)
        .animation(.easeInOut(duration: 0.2), value: model.missingPermissions.count)
        .onAppear { model.actions.refresh() }
    }
}

private struct PopoverDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 14)
    }
}

// MARK: - Header

/// "Glasspad" in bold with the on switch, like the Wi-Fi menu. Off pauses Glasspad.
private struct HeaderRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            Text("Glasspad")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Toggle("Glasspad", isOn: Binding(get: { !model.isPaused }, set: { model.actions.setPaused(!$0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(model.isPaused ? "Resume Glasspad" : "Pause Glasspad")
                .help(model.isPaused ? "Turn on to let your iPhone connect." : "Turn off to stop listening for your iPhone.")
        }
    }
}

// MARK: - Status

/// The iPhone as a device row: a round icon, filled with the accent colour while connected,
/// the name or state, one line under it, and the signal.
private struct StatusRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(model.isConnected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.isConnected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(model.statusDetail)
                    .font(.system(size: 11))
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
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
                PermissionRow(kind: item == .accessibility ? .accessibility : .media)
            }
        }
    }
}

// MARK: - Pairing

private struct PairingSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.pairing.isActive {
            VStack(spacing: 10) {
                PairingPanel(qrSize: 216) { model.actions.cancelPairing() }
                if case .paired = model.pairing {
                    EmptyView()
                } else {
                    Button("Cancel") { model.actions.cancelPairing() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        } else {
            Button {
                model.actions.beginPairing()
            } label: {
                PopoverRow(symbol: "qrcode", title: PairingCopy.menuItem)
            }
            .buttonStyle(PopoverRowButtonStyle())
            .disabled(model.isPaused)
        }
    }
}

// MARK: - Dock

/// Hide Mac Dock, a switch row with the same round icon as the rows around it.
private struct DockRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PopoverRow(symbol: "dock.rectangle", title: "Hide Mac Dock", active: model.dock.hidden) {
            Toggle("Hide Mac Dock", isOn: Binding(get: { model.dock.hidden }, set: { model.actions.setDockHidden($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .help("Your Dock settings come back as they were when you turn this off or quit.")
    }
}

/// A round icon (accent filled while `active`), the title, then anything trailing. Every row
/// in the popover lines up on it, as in the system's menu bar extras.
private struct PopoverRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var active = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension PopoverRow where Trailing == EmptyView {
    init(symbol: String, title: String, active: Bool = false) {
        self.init(symbol: symbol, title: title, active: active) { EmptyView() }
    }
}

// MARK: - Footer

private struct FooterButtons: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsLink {
                Text("Glasspad Settings…")
                    .font(.system(size: 13))
            }
            .buttonStyle(PopoverRowButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            .keyboardShortcut(",")
            Button {
                model.actions.quit()
            } label: {
                Text("Quit Glasspad")
                    .font(.system(size: 13))
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
