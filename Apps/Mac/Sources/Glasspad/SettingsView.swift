import GlasspadKit
import GlasspadMacCore
import SwiftUI

/// The standard Settings window: toolbar tabs, one grouped Form per tab.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { t in
                t.pane
                    .frame(width: t.size.width, height: t.size.height)
                    .tabItem { Label(t.title, systemImage: t.symbol) }
                    .tag(t)
            }
        }
        .onAppear { model.actions.refresh() }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, iphone, trackpad, macros, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .iphone: "iPhone"
        case .trackpad: "Trackpad"
        case .macros: "Macros"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .iphone: "iphone"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .macros: "wand.and.stars"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }

    /// Each pane's content size; the window animates between them as System Settings does.
    var size: CGSize {
        switch self {
        case .general: CGSize(width: 520, height: 480)
        case .iphone: CGSize(width: 520, height: 300)
        case .trackpad: CGSize(width: 520, height: 470)
        case .macros: CGSize(width: 780, height: 560)
        case .advanced: CGSize(width: 520, height: 240)
        case .about: CGSize(width: 520, height: 330)
        }
    }

    @MainActor @ViewBuilder
    var pane: some View {
        switch self {
        case .general: GeneralPane()
        case .iphone: IPhonePane()
        case .trackpad: TrackpadPane()
        case .macros: MacrosSettings()
        case .advanced: AdvancedPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - Row pieces

/// A Form row label: tinted icon tile, title, and an optional line of explanation.
struct RowLabel: View {
    let title: String
    var detail: String?
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            SettingsIcon(symbol: symbol, color: color)
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.actions.setLaunchAtLogin($0) })) {
                    RowLabel(title: "Open at Login", symbol: "power", color: .gray)
                }
                if model.launchNeedsApproval {
                    LabeledContent {
                        Button("Open Login Items…") { model.actions.openLoginItems() }
                    } label: {
                        Text("Allow Glasspad in Login Items to finish turning this on.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker(selection: Binding(get: { MacDockHiding(model.dock) }, set: { model.actions.setDockHiding($0) })) {
                    ForEach(MacDockHiding.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    RowLabel(title: "Hide Mac Dock", symbol: "dock.rectangle", color: .blue)
                }
            } header: {
                Text("Mac Dock")
            } footer: {
                Text(MacDockHiding.footer)
                    .foregroundStyle(.secondary)
            }

            Section {
                PermissionRow(kind: .accessibility, iconSize: 20)
                PermissionRow(kind: .media, iconSize: 20)
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - iPhone

struct IPhonePane: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmForget: StoredPhone?

    var body: some View {
        Form {
            Section {
                if model.phones.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "iphone.gen3")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("No iPhones Paired")
                                .font(.headline)
                            Text("Pair your iPhone to use it as a trackpad and remote.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(model.phones) { phone in
                    LabeledContent {
                        HStack(spacing: 10) {
                            if isConnected(phone), let battery = model.phoneBattery {
                                PhoneBatteryLabel(battery: battery)
                            }
                            Button("Forget…") { confirmForget = phone }
                                .accessibilityLabel("Forget \(phone.phoneName)")
                        }
                    } label: {
                        RowLabel(title: phone.phoneName, detail: detail(for: phone),
                                 symbol: "iphone", color: isConnected(phone) ? .green : .gray)
                    }
                }
            } header: {
                Text("Paired iPhones")
            } footer: {
                HStack {
                    Spacer()
                    Button(PairingCopy.menuItem) {
                        model.actions.beginPairing()
                    }
                    .disabled(model.isPaused)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(get: { model.pairing.isActive },
                                    set: { if !$0 { model.actions.cancelPairing() } })) {
            PairingSheet()
        }
        .confirmationDialog("Forget “\(confirmForget?.phoneName ?? "")”?",
                            isPresented: Binding(get: { confirmForget != nil }, set: { if !$0 { confirmForget = nil } }),
                            presenting: confirmForget) { phone in
            Button("Forget iPhone", role: .destructive) { model.actions.forget(phone) }
        } message: { _ in
            Text("It disconnects now and has to be paired again to use this Mac.")
        }
    }

    private func isConnected(_ phone: StoredPhone) -> Bool {
        model.isConnected && model.connectedPhoneName == phone.phoneName
    }

    private func detail(for phone: StoredPhone) -> String {
        if isConnected(phone) {
            if let s = model.signal { return "Connected, \(s.title.lowercased()) signal" }
            return "Connected"
        }
        return "Paired \(phone.pairedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct PairingSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            if model.pairing.url != nil {
                Text(PairingCopy.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            PairingPanel(qrSize: 240) { model.actions.cancelPairing() }
            HStack {
                Spacer()
                if case .paired = model.pairing {
                    Button("Done") { model.actions.cancelPairing() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { model.actions.cancelPairing() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Trackpad

struct TrackpadPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Trackpad Settings…") { model.actions.openTrackpadSettings() }
                } label: {
                    Text("Speed, scrolling and gestures")
                    Text("Glasspad follows this Mac's trackpad settings. Pointer feel is set in Glasspad on your iPhone.")
                }
            }

            Section {
                ForEach(GestureCopy.adjustable, id: \.self) { g in
                    Picker(selection: Binding(get: { model.gesturePreferences.preference(for: g) },
                                              set: { model.actions.setGesturePreference($0, g) })) {
                        ForEach(GesturePreference.options(for: g), id: \.self) { p in
                            Text(GestureCopy.choice(p)).tag(p)
                        }
                    } label: {
                        Text(g.displayName)
                        if let line = GestureCopy.inUse(model.capabilities.mode(for: g)) { Text(line) }
                    }
                }
            } header: {
                Text(GestureCopy.sectionTitle)
            } footer: {
                Text(GestureCopy.footer)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

}

// MARK: - Advanced

struct AdvancedPane: View {
    @EnvironmentObject private var model: AppModel

    /// The snapshot harness used to open a Diagnostics group here; there is none now.
    init(diagnosticsExpanded: Bool = false) {}

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.allowShellButtons }, set: { model.actions.setAllowShellButtons($0) })) {
                    Text("Allow shell command buttons")
                    Text("Commands run as you. Leave this off unless you wrote them yourself.")
                }
                LabeledContent("Macros folder") {
                    Button("Show in Finder") { model.actions.showMacrosFolder() }
                }
            } header: {
                Text("Actions and Macros")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutPane: View {
    /// The harness passes the asset catalog's icon and a fixed version; the app reads its bundle.
    var icon: NSImage?
    var version: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: icon ?? AppInfoText.icon)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Glasspad")
                .font(.title.weight(.semibold))
                .padding(.top, 4)
            Text(version ?? AppInfoText.version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(WelcomeCopy.helloDetail)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Text("It talks only to your paired iPhone, encrypted with a key only the two share.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Source Code", destination: URL(string: "https://github.com/Soham109/glasspad")!)
                Link("Report a Problem", destination: URL(string: "https://github.com/Soham109/glasspad/issues")!)
            }
            .padding(.top, 10)
            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
