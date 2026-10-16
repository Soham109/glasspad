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
        case .general: CGSize(width: 520, height: 540)
        case .iphone: CGSize(width: 520, height: 400)
        case .trackpad: CGSize(width: 520, height: 640)
        case .macros: CGSize(width: 780, height: 560)
        case .advanced: CGSize(width: 520, height: 640)
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
                Toggle(isOn: Binding(get: { model.isPaused }, set: { model.actions.setPaused($0) })) {
                    RowLabel(title: "Pause Glasspad", detail: "Your iPhone cannot connect while Glasspad is paused.",
                             symbol: "pause.fill", color: .orange)
                }
            }

            Section {
                Toggle(isOn: Binding(get: { model.dock.hidden }, set: { model.actions.setDockHidden($0) })) {
                    RowLabel(title: "Hide Mac Dock", symbol: "dock.rectangle", color: .blue)
                }
                Toggle(isOn: Binding(get: { model.dock.hideWhileConnected },
                                     set: { model.actions.setHideDockWhileConnected($0) })) {
                    RowLabel(title: "Hide While iPhone Is Connected", symbol: "iphone", color: .blue)
                }
            } header: {
                Text("Mac Dock")
            } footer: {
                Text("Glasspad saves your Dock settings before hiding it and puts them back exactly when you turn this off, when your iPhone disconnects, and when Glasspad quits.")
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
                        Button("Forget…") { confirmForget = phone }
                            .accessibilityLabel("Forget \(phone.phoneName)")
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

            Section {
                LabeledContent("Shown on iPhone as", value: model.macName)
            } header: {
                Text("This Mac")
            } footer: {
                Text("Your iPhone finds this Mac on the same Wi-Fi network, or directly when there is no shared network. Everything between them is encrypted with the key made when you paired.")
                    .foregroundStyle(.secondary)
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
        let s = model.settings
        let t = s.tuning
        Form {
            Section {
                LabeledContent("Tracking speed", value: String(format: "%.1f of 3", s.trackingSpeed))
                LabeledContent("Natural scrolling", value: s.naturalScrolling ? "On" : "Off")
                LabeledContent("Secondary click", value: s.secondaryClick.text)
                LabeledContent("Look up", value: s.lookUp.text)
                LabeledContent("Swipe between pages", value: s.swipeBetweenPages.text)
                LabeledContent("Swipe between spaces", value: s.swipeBetweenSpaces.text)
                LabeledContent("Mission Control", value: s.missionControl.text)
                LabeledContent("App Exposé", value: s.appExpose.text)
            } header: {
                Text("From This Mac")
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Glasspad follows your Mac's trackpad settings and updates when you change them. Tap to click is always on.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Trackpad Settings…") { model.actions.openTrackpadSettings() }
                        .fixedSize()
                }
            }

            Section {
                LabeledContent("Pointer speed", value: multiplier(t.pointerSpeed))
                LabeledContent("Acceleration", value: t.acceleration.text)
                LabeledContent("Scroll speed", value: multiplier(t.scrollSpeed))
                LabeledContent("Momentum", value: t.momentumStrength == 0 ? "Off" : multiplier(t.momentumStrength))
                LabeledContent("Click haptics", value: percent(t.clickHaptic))
                LabeledContent("Force click haptics", value: percent(t.forceClickHaptic))
                LabeledContent("Drag lock haptics", value: percent(t.dragLockHaptic))
            } header: {
                Text("Feel, Set on iPhone")
            } footer: {
                Text("Change these in Glasspad on your iPhone, under Settings > Feel. This Mac keeps them and uses them for every gesture.")
                    .foregroundStyle(.secondary)
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
                        Text(GestureCopy.inUse(model.capabilities.mode(for: g)))
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

    private func multiplier(_ v: Double) -> String {
        if abs(v - 1) < 0.005 { return "Same as Mac" }
        let n = v.formatted(.number.precision(.fractionLength(0...2)))
        return v > 1 ? "\(n)× faster" : "\(n)× Mac"
    }

    private func percent(_ v: Double) -> String {
        v == 0 ? "Off" : v.formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var showDiagnostics: Bool

    /// The harness opens Diagnostics to draw it; the app starts with it closed.
    init(diagnosticsExpanded: Bool = false) {
        _showDiagnostics = State(initialValue: diagnosticsExpanded)
    }

    var body: some View {
        let stats = model.stats
        Form {
            Section {
                LabeledContent("Status", value: model.statusTitle)
                LabeledContent("Signal", value: model.signal?.title ?? "Not connected")
                DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                    LabeledContent("Round trip, typical", value: formatMilliseconds(stats.rttMedianMs))
                    LabeledContent("Round trip, slowest 5%", value: formatMilliseconds(stats.rttP95Ms))
                    LabeledContent("Touch updates received", value: stats.framesReceived.formatted())
                    LabeledContent("Rejected packets", value: rejected(stats).formatted())
                        .help("Packets that failed the encryption check, arrived twice, or could not be read. A few are normal on busy networks.")
                    LabeledContent {
                        Text(model.clipboardRefusal == nil ? "None" : "Not sent")
                    } label: {
                        Text("Last clipboard problem")
                        if let refusal = model.clipboardRefusal { Text(refusal) }
                    }
                    Text("How each gesture reaches this Mac")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    ForEach(model.capabilities.summary, id: \.gesture) { item in
                        LabeledContent(item.gesture.displayName,
                                       value: GestureCopy.diagnostics(item.mode, preference: model.gesturePreferences.preference(for: item.gesture)))
                            .help(item.mode.help)
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("A trackpad gesture follows your fingers. A keyboard shortcut plays all at once. Choose per gesture in Trackpad settings.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: Binding(get: { model.allowShellButtons }, set: { model.actions.setAllowShellButtons($0) })) {
                    Text("Allow shell command buttons in Actions")
                    Text("Commands run with your user account. Leave this off unless you wrote them yourself.")
                }
                LabeledContent("Pinned and Library file") {
                    Button("Show in Finder") { model.actions.showActionsFile() }
                }
                LabeledContent("Macros folder") {
                    Button("Show in Finder") { model.actions.showMacrosFolder() }
                }
            } header: {
                Text("Actions")
            }

            Section {
                LabeledContent {
                    Button("Open Console") { model.actions.openConsole() }
                } label: {
                    Text("Logs")
                    Text("In Console, search for com.soham109.glasspad.")
                }
                LabeledContent {
                    Button("Check Again") { model.actions.recheckPermissions() }
                } label: {
                    Text("Permissions")
                    Text(model.missingPermissions.isEmpty ? "Everything Glasspad needs is allowed." : "Something needs your OK. See General.")
                }
            } header: {
                Text("Troubleshooting")
            }
        }
        .formStyle(.grouped)
    }

    private func rejected(_ s: LinkStats) -> Int { s.authFailures + s.replayDrops + s.malformed }
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
            Text("Your iPhone as a wireless trackpad and remote for your Mac.")
                .multilineTextAlignment(.center)
                .padding(.top, 8)
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

// MARK: - Text for trackpad values

private extension SecondaryClick {
    var text: String {
        switch self {
        case .twoFinger: "Two fingers"
        case .bottomRight: "Bottom right corner"
        case .bottomLeft: "Bottom left corner"
        case .off: "Off"
        }
    }
}

private extension LookUp {
    var text: String {
        switch self {
        case .forceClick: "Force click"
        case .threeFingerTap: "Three finger tap"
        case .off: "Off"
        }
    }
}

private extension SwipePages {
    var text: String {
        switch self {
        case .twoFinger: "Two fingers"
        case .threeFinger: "Three fingers"
        case .twoOrThree: "Two or three fingers"
        case .off: "Off"
        }
    }
}

private extension FingerCount {
    var text: String {
        switch self {
        case .three: "Three fingers"
        case .four: "Four fingers"
        case .off: "Off"
        }
    }
}

private extension PointerAcceleration {
    var text: String {
        switch self {
        case .mac: "Same as Mac"
        case .linear: "Steady"
        case .off: "Off"
        }
    }
}
