import SwiftUI
import GlasspadKit

/// Phone settings. The main page holds what people change; rare
/// options live under Advanced.
struct SettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    var store = PairingStore.shared

    @State private var showPair = false
    @State private var macToForget: PairedMac?
    @State private var debugPage: String?

    var body: some View {
        NavigationStack {
            Form {
                look
                trackpad
                modes
                macs
                more
            }
            .scrollContentBackground(.hidden)
            .background(SurfaceBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if #available(iOS 26.0, *) {
                        Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                    } else {
                        Button("Done") { dismiss() }.fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showPair) { PairSheet().presentationDragIndicator(.visible) }
            #if DEBUG
            .navigationDestination(isPresented: Binding(get: { debugPage != nil }, set: { if !$0 { debugPage = nil } })) {
                switch debugPage {
                case "setup": SetupChecklistView(inSettings: true)
                case "advanced": AdvancedSettings()
                case "haptics": HapticsSettings()
                case "pointer": PointerSettings()
                case "dock": ModeDetailSettings(mode: .dock)
                default: ConnectionHelpView()
                }
            }
            .onAppear {
                if let page = DebugLaunch.settingsPage {
                    DebugLaunch.settingsPage = nil
                    debugPage = page
                }
            }
            #endif
            .confirmationDialog("Forget this Mac?", isPresented: .init(get: { macToForget != nil },
                                                                      set: { if !$0 { macToForget = nil } }),
                                titleVisibility: .visible, presenting: macToForget) { mac in
                Button("Forget \(mac.name)", role: .destructive) {
                    session.forget(mac)
                }
            } message: { _ in
                Text("To use it again, you will need to pair again.")
            }
        }
        .tint(palette.inkColor)
    }

    // MARK: Sections

    private var look: some View {
        Section("Appearance") {
            ThemePicker(selection: $settings.theme)
                .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
            NavigationLink {
                FingerDotSettings()
            } label: {
                LabeledContent {
                    Text(settings.showDots ? settings.dotSizeChoice.title : "Off")
                } label: {
                    Label("Finger Dots", systemImage: "circle.dotted.circle")
                }
            }
        }
        .listRowBackground(palette.raisedColor)
    }

    private var trackpad: some View {
        Section {
            Picker(selection: $settings.orientation) {
                ForEach(OrientationChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            } label: {
                Label("Orientation", systemImage: "rotate.right")
            }
            NavigationLink {
                PointerSettings()
            } label: {
                Label("Pointer and Scrolling", systemImage: "cursorarrow.motionlines")
            }
            NavigationLink {
                HapticsSettings()
            } label: {
                LabeledContent {
                    Text(settings.hapticStrength < 0.01 ? "Off" : settings.hapticStrength.formatted(.percent.precision(.fractionLength(0))))
                } label: {
                    Label("Haptics", systemImage: "waveform")
                }
            }
        } header: {
            Text("Trackpad")
        } footer: {
            Text("A tap is a click. To force click, rest one finger for a moment.")
        }
        .listRowBackground(palette.raisedColor)
    }

    private var modes: some View {
        Section("Modes") {
            NavigationLink {
                ModesSettings()
            } label: {
                LabeledContent {
                    Text("\(AppMode.visible.count) Shown")
                } label: {
                    Label("Show and Reorder", systemImage: "square.grid.2x2")
                }
            }
            ForEach(AppMode.visible.filter { $0.hasSettings }) { mode in
                NavigationLink {
                    ModeDetailSettings(mode: mode)
                } label: {
                    Label {
                        Text(mode.title)
                    } icon: {
                        Image(systemName: mode.symbol).foregroundStyle(mode.accent(palette))
                    }
                }
            }
        }
        .listRowBackground(palette.raisedColor)
    }

    private var macs: some View {
        Section {
            ForEach(store.macs) { mac in
                Button {
                    session.select(mac)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "laptopcomputer")
                            .foregroundStyle(palette.inkSoftColor)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mac.name).foregroundStyle(palette.inkColor)
                            Text(statusLine(for: mac))
                                .font(.footnote)
                                .foregroundStyle(palette.inkSoftColor)
                        }
                        Spacer()
                        if store.selected?.macID == mac.macID {
                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(palette.inkColor)
                        }
                    }
                }
                .swipeActions {
                    Button("Forget", role: .destructive) { macToForget = mac }
                }
                .contextMenu {
                    Button("Forget", systemImage: "trash", role: .destructive) { macToForget = mac }
                }
            }
            if store.selected != nil {
                NavigationLink {
                    ConnectionHelpView()
                } label: {
                    LabeledContent {
                        Text(session.macNeedsAccessibility ? "Needs Permission" : session.state.isConnectedState ? "Connected" : "Not Connected")
                    } label: {
                        Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                if !settings.setupComplete {
                    NavigationLink {
                        SetupChecklistView(inSettings: true)
                    } label: {
                        Label("Finish Setting Up", systemImage: "checklist")
                    }
                }
            }
            if !session.isConnected, store.selected?.wakeTarget != nil {
                LinkActions()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            Button {
                showPair = true
            } label: {
                Label(store.macs.isEmpty ? "Pair a Mac" : "Pair Another Mac", systemImage: "qrcode.viewfinder")
                    .foregroundStyle(palette.inkColor)
            }
        } header: {
            Text(store.macs.count > 1 ? "Macs" : "Mac")
        } footer: {
            if store.macs.count > 1 { Text("Tap a Mac to use it. Swipe left to forget one.") }
        }
        .listRowBackground(palette.raisedColor)
    }

    private var more: some View {
        Section {
            NavigationLink {
                AdvancedSettings()
            } label: {
                Label("Advanced", systemImage: "gearshape.2")
            }
            NavigationLink {
                AboutSettings()
            } label: {
                Label("About", systemImage: "info.circle")
            }
        }
        .listRowBackground(palette.raisedColor)
    }

    // MARK: Helpers

    private func statusLine(for mac: PairedMac) -> String {
        if store.selected?.macID == mac.macID {
            return session.state.statusText
        }
        return "Paired " + mac.pairedAt.formatted(date: .abbreviated, time: .omitted)
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        if seconds == 0 { return "Never" }
        return seconds < 60 ? "\(Int(seconds)) seconds" : (seconds == 60 ? "1 minute" : "\(Int(seconds / 60)) minutes")
    }
}

/// Rare options, kept off the main page: handedness, where the mode button sits, which mode opens,
/// the screen staying on, this iPhone's name, and putting the look back.
struct AdvancedSettings: View {
    @Environment(\.palette) private var palette
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.leftHanded) {
                    Label("Left-Handed", systemImage: "hand.raised")
                }
                Picker(selection: $settings.pillPosition) {
                    ForEach(PillPosition.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Mode Button", systemImage: "capsule")
                }
                Picker(selection: $settings.launchMode) {
                    Text("Last Used").tag(AppMode?.none)
                    ForEach(AppMode.visible) { Text($0.title).tag(AppMode?.some($0)) }
                } label: {
                    Label("Start In", systemImage: "arrow.forward.square")
                }
            } footer: {
                Text("Start In is the mode Glasspad shows when you open it. Left-Handed moves the big buttons in Keyboard and Present to the left.")
            }
            .listRowBackground(palette.raisedColor)

            Section {
                Toggle(isOn: $settings.keepScreenAwake) {
                    Label("Keep Screen On", systemImage: "sun.max")
                }
                .onChange(of: settings.keepScreenAwake) { ScreenAwake.update() }
                if settings.keepScreenAwake {
                    Picker(selection: $settings.dimDelay) {
                        ForEach(PhoneSettings.dimDelayChoices, id: \.self) { delay in
                            Text(SettingsView.durationText(delay)).tag(delay)
                        }
                    } label: {
                        Label("Dim After", systemImage: "moon")
                    }
                }
            } footer: {
                Text("On the trackpad and in Present, the screen stays on and dims when you stop touching it.")
            }
            .listRowBackground(palette.raisedColor)

            Section {
                LabeledContent {
                    TextField("iPhone", text: $settings.phoneName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(palette.inkSoftColor)
                        .submitLabel(.done)
                        .onSubmit { session.reconnect() }
                } label: {
                    Label("Name", systemImage: "iphone")
                }
            } footer: {
                Text("Your Mac shows this iPhone by this name.")
            }
            .listRowBackground(palette.raisedColor)

            Section {
                if settings.setupComplete, PairingStore.shared.selected != nil {
                    NavigationLink("Setup Checklist") { SetupChecklistView(inSettings: true) }
                }
                Button("Reset Appearance and Haptics", role: .destructive) { confirmReset = true }
            }
            .listRowBackground(palette.raisedColor)
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: settings.keepScreenAwake)
        .confirmationDialog("Reset appearance and haptics?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                Haptics.shared.tap()
                ThemeTransition.run { settings.resetLookAndFeel() }
                session.refreshHapticStrength()
            }
        } message: {
            Text("Theme, finger dots, haptics and Dock icon size go back to how Glasspad ships.")
        }
    }
}

/// Version, source and the privacy promise.
struct AboutSettings: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: Bundle.main.versionString)
                Link(destination: URL(string: "https://github.com/Soham109/glasspad")!) {
                    LabeledContent {
                        Image(systemName: "arrow.up.right").foregroundStyle(palette.inkSoftColor)
                    } label: {
                        Text("Source Code").foregroundStyle(palette.inkColor)
                    }
                }
            } footer: {
                Text("Glasspad is free and open source. It talks only to your paired Mac, encrypted with a key only the two of them share. No accounts, no servers, no tracking.")
            }
            .listRowBackground(palette.raisedColor)
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Theme picker

/// Changes the theme with a quick cross fade of the whole window, so every screen, sheet and
/// system control changes together instead of one piece at a time.
enum ThemeTransition {
    @MainActor static func run(_ change: @escaping () -> Void) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.bounds.width > 0 }
        guard !UIAccessibility.isReduceMotionEnabled, let window = windows.first(where: \.isKeyWindow) ?? windows.first else {
            change()
            return
        }
        UIView.transition(with: window, duration: 0.35, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            change()
        }
    }
}

/// Every theme as a small live phone screen: four to a row in portrait, all in one row when
/// the sheet is wide.
private struct ThemePicker: View {
    @Binding var selection: ThemeChoice

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 66, maximum: 92), spacing: 10)], spacing: 14) {
            ForEach(ThemeChoice.allCases) { choice in
                ThemeSwatch(choice: choice, selected: selection == choice) {
                    guard selection != choice else { return }
                    Haptics.shared.tap()
                    ThemeTransition.run { selection = choice }
                }
            }
        }
    }
}

/// One theme: a miniature screen in its own colours with its name under it. Themes that
/// follow the iPhone show their light and dark halves side by side.
private struct ThemeSwatch: View {
    @Environment(\.palette) private var palette
    let choice: ThemeChoice
    let selected: Bool
    let action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Group {
                    if choice.interfaceStyle == .unspecified {
                        HStack(spacing: 0) {
                            ThemeMiniature(palette: choice.preview(dark: false), half: .leading)
                            ThemeMiniature(palette: choice.preview(dark: true), half: .trailing)
                        }
                    } else {
                        ThemeMiniature(palette: choice.preview(dark: choice.interfaceStyle == .dark), half: nil)
                    }
                }
                .aspectRatio(0.72, contentMode: .fit)
                .clipShape(shape)
                .overlay { shape.strokeBorder(palette.lineColor, lineWidth: 1) }
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(selected ? palette.inkColor : .clear, lineWidth: 2)
                }
                Text(choice.title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? palette.inkColor : palette.inkSoftColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A theme drawn small: the mode pill, four tiles (two tinted, as colour shows in that
/// theme) and a line of text, on the theme's own surface. `half` draws only that side of the
/// layout, so a light and a dark half join into one screen.
private struct ThemeMiniature: View {
    let palette: Palette
    let half: HorizontalAlignment?

    var body: some View {
        GeometryReader { proxy in
            let full = proxy.size.width * (half == nil ? 1 : 2)
            screen(width: full)
                .frame(width: full, height: proxy.size.height)
                .offset(x: half == .trailing ? -proxy.size.width : 0)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .clipped()
        }
        .environment(\.colorScheme, palette.colorScheme)
        .accessibilityHidden(true)
    }

    private func screen(width: CGFloat) -> some View {
        let tile = (width - 22) / 2
        return ZStack(alignment: .top) {
            surface
            VStack(spacing: 6) {
                Capsule()
                    .fill(Color(uiColor: palette.raised))
                    .overlay(Capsule().strokeBorder(Color(uiColor: palette.line), lineWidth: 0.5))
                    .frame(width: width * 0.42, height: 9)
                    .padding(.top, 7)
                    .padding(.bottom, 3)
                HStack(spacing: 6) {
                    self.tile(palette.tint(Color(uiColor: .systemOrange)), "bolt.fill", side: tile)
                    self.tile(palette.tint(Color(uiColor: .systemBlue)), "safari.fill", side: tile)
                }
                HStack(spacing: 6) {
                    self.tile(Color(uiColor: palette.ink), "moon.fill", side: tile)
                    self.tile(Color(uiColor: palette.ink), "speaker.wave.2.fill", side: tile)
                }
            }
        }
    }

    @ViewBuilder private var surface: some View {
        if palette.glass {
            Image(uiImage: (palette.isDark ? Backdrop.dark : Backdrop.light).image)
                .resizable()
                .scaledToFill()
        } else {
            Color(uiColor: palette.background)
        }
    }

    private func tile(_ tint: Color, _ symbol: String, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(uiColor: palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color(uiColor: palette.line), lineWidth: 0.5))
            .overlay(Image(systemName: symbol).font(.system(size: side * 0.36, weight: .semibold)).foregroundStyle(tint))
            .frame(width: side, height: side * 0.86)
    }
}

extension ClickPressure {
    var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .firm: "Firm"
        }
    }

    /// How much this Mac setting scales the phone's haptic strength.
    var hapticScale: Double {
        switch self {
        case .light: 0.75
        case .medium: 1.0
        case .firm: 1.25
        }
    }
}

extension SecondaryClick {
    var title: String {
        switch self {
        case .twoFinger: "Two fingers"
        case .bottomRight: "Bottom right corner"
        case .bottomLeft: "Bottom left corner"
        case .off: "Off"
        }
    }
}

extension FingerCount {
    var title: String {
        switch self {
        case .three: "Three fingers"
        case .four: "Four fingers"
        case .off: "Off"
        }
    }
}

extension Bundle {
    var versionString: String {
        let v = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let b = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }
}
