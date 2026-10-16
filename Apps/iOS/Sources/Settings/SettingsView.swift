import SwiftUI
import GlasspadKit

/// Phone settings, opened by long pressing the mode pill.
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
                clickingNote
                look
                trackpad
                feel
                screen
                modes
                macs
                about
            }
            .scrollContentBackground(.hidden)
            .background(palette.backgroundColor.ignoresSafeArea())
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
                if debugPage == "setup" { SetupChecklistView(inSettings: true) } else { ConnectionHelpView() }
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
                Text("This iPhone deletes its key for that Mac. To use it again, pair again. You can also revoke this phone from the Mac menu.")
            }
        }
        .tint(palette.inkColor)
    }

    // MARK: Sections

    private var clickingNote: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 22))
                    .foregroundStyle(palette.inkColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap is click")
                        .font(.headline)
                    Text("An iPhone cannot feel how hard you press, so a tap always clicks. Hold one finger still for a moment to force click.")
                        .font(.subheadline)
                        .foregroundStyle(palette.inkSoftColor)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(palette.raisedColor)
    }

    private var look: some View {
        Section("Look") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                ForEach(ThemeChoice.allCases) { choice in
                    ThemeSwatch(choice: choice, selected: settings.theme == choice) {
                        Haptics.shared.tap()
                        withAnimation(.easeInOut(duration: 0.25)) { settings.theme = choice }
                    }
                }
            }
            .padding(.vertical, 8)
            NavigationLink {
                FingerDotSettings()
            } label: {
                LabeledContent {
                    Text(settings.showDots ? settings.dotStyle.title : "Off")
                } label: {
                    Label("Finger Dots", systemImage: "circle.dotted.circle")
                }
            }
            Picker(selection: $settings.pillPosition) {
                ForEach(PillPosition.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Mode Pill", systemImage: "capsule")
            }
            Toggle(isOn: $settings.leftHanded) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Left-Handed")
                        Text("Puts the main buttons on the left in Keyboard and Present.")
                            .font(.footnote).foregroundStyle(palette.inkSoftColor)
                    }
                } icon: {
                    Image(systemName: "hand.raised")
                }
            }
        }
        .listRowBackground(palette.raisedColor)
    }

    private var feel: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Haptic Strength", systemImage: "waveform")
                    Spacer()
                    Text(settings.hapticStrength < 0.01 ? "Off" : settings.hapticStrength.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(palette.inkSoftColor)
                }
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.1").foregroundStyle(palette.inkSoftColor).accessibilityHidden(true)
                    Slider(value: $settings.hapticStrength, in: 0...1) { editing in
                        if !editing {
                            session.refreshHapticStrength()
                            Haptics.shared.play(.click)
                        }
                    }
                    .accessibilityLabel("Haptic strength")
                    Image(systemName: "speaker.wave.3").foregroundStyle(palette.inkSoftColor).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            NavigationLink {
                HapticKindsSettings()
            } label: {
                LabeledContent {
                    Text(settings.hapticsOff.isEmpty ? "All On" : "\(HapticChannel.allCases.count - settings.hapticsOff.count) of \(HapticChannel.allCases.count)")
                } label: {
                    Label("Haptic Types", systemImage: "slider.horizontal.3")
                }
            }
            if !Haptics.shared.isSupported {
                Text("This device has no Taptic Engine, so there is nothing to feel.")
                    .font(.footnote).foregroundStyle(palette.inkSoftColor)
            }
        } header: {
            Text("Haptics")
        } footer: {
            Text("Firmness also follows Click on your Mac (\(session.trackpadSettings.clickPressure.title)).")
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
        } header: {
            Text("Trackpad")
        } footer: {
            Text("Held sideways, your iPhone is the shape of a Mac trackpad. You can also lock rotation from the mode menu.")
        }
        .listRowBackground(palette.raisedColor)
    }

    private var screen: some View {
        Section {
            Toggle(isOn: $settings.keepScreenAwake) {
                Label("Keep Screen On", systemImage: "sun.max")
            }
            .onChange(of: settings.keepScreenAwake) { ScreenAwake.update() }
            Picker(selection: $settings.dimDelay) {
                ForEach(PhoneSettings.dimDelayChoices, id: \.self) { delay in
                    Text(Self.durationText(delay)).tag(delay)
                }
            } label: {
                Label("Dim After", systemImage: "moon")
            }
            .disabled(!settings.keepScreenAwake)
        } header: {
            Text("Screen")
        } footer: {
            Text("On the trackpad and in Present, the screen stays on and dims when you stop touching it. The next touch wakes it.")
        }
        .listRowBackground(palette.raisedColor)
    }

    private var modes: some View {
        Section {
            NavigationLink {
                ModesSettings()
            } label: {
                LabeledContent {
                    Text("\(AppMode.visible.count) shown")
                } label: {
                    Label("Modes", systemImage: "square.grid.2x2")
                }
            }
            Picker(selection: $settings.launchMode) {
                Text("Last Used").tag(AppMode?.none)
                ForEach(AppMode.visible) { Text($0.title).tag(AppMode?.some($0)) }
            } label: {
                Label("Open In", systemImage: "arrow.forward.square")
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
        } header: {
            Text("Modes")
        } footer: {
            Text("Choose which modes the pill shows, and in what order.")
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
                        Text(session.macNeedsAccessibility ? "Needs permission" : session.state.isConnectedState ? "Connected" : "Help")
                    } label: {
                        Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                NavigationLink {
                    SetupChecklistView(inSettings: true)
                } label: {
                    LabeledContent {
                        Text(settings.setupComplete ? "Done" : "Not finished")
                    } label: {
                        Label("Setup Checklist", systemImage: "checklist")
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
                Label("Pair a Mac", systemImage: "qrcode.viewfinder")
                    .foregroundStyle(palette.inkColor)
            }
            HStack {
                Label("This iPhone's Name", systemImage: "iphone")
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()
                TextField("iPhone", text: $settings.phoneName)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160)
                    .foregroundStyle(palette.inkSoftColor)
                    .submitLabel(.done)
                    .onSubmit { session.reconnect() }
            }
        } header: {
            Text("Macs")
        } footer: {
            Text(store.macs.isEmpty ? "No Mac paired yet." : "Swipe left on a Mac to forget it. Your Mac shows this iPhone by the name above.")
        }
        .listRowBackground(palette.raisedColor)
    }

    private var about: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.versionString)
            Link(destination: URL(string: "https://github.com/Soham109/glasspad")!) {
                HStack {
                    Text("Source Code").foregroundStyle(palette.inkColor)
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(palette.inkSoftColor)
                }
            }
            Button("Reset Look and Feel", role: .destructive) {
                Haptics.shared.tap()
                settings.resetLookAndFeel()
                session.refreshHapticStrength()
            }
            Text("Free and open source. Glasspad talks only to your paired Mac, encrypted with a key only the two of them have. No accounts, no servers, no tracking.")
                .font(.footnote)
                .foregroundStyle(palette.inkSoftColor)
                .padding(.vertical, 2)
        } header: {
            Text("About")
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

/// A live miniature of a theme: its surface, two tiles and a line of text, drawn in the
/// theme's own colours. Themes that follow the iPhone show their light and dark halves.
private struct ThemeSwatch: View {
    @Environment(\.palette) private var palette
    let choice: ThemeChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if choice.interfaceStyle == .unspecified {
                        HStack(spacing: 0) {
                            ThemeMiniature(palette: choice.preview(dark: false))
                            ThemeMiniature(palette: choice.preview(dark: true))
                        }
                    } else {
                        ThemeMiniature(palette: choice.preview(dark: choice.interfaceStyle == .dark))
                    }
                }
                .frame(height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.lineColor, lineWidth: 1)
                }
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(selected ? palette.inkColor : .clear, lineWidth: 2)
                }
                Text(choice.title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? palette.inkColor : palette.inkSoftColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.title) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The theme drawn small: two tiles (one tinted, as colour shows in that theme) and two
/// lines of text on the surface.
private struct ThemeMiniature: View {
    let palette: Palette

    var body: some View {
        ZStack {
            Color(uiColor: palette.background)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    tile(palette.tint(Color(uiColor: .systemOrange)), "bolt.fill")
                    tile(palette.tint(Color(uiColor: .systemBlue)), "safari.fill")
                }
                Capsule().fill(Color(uiColor: palette.ink)).frame(width: 30, height: 4)
                Capsule().fill(Color(uiColor: palette.inkSoft)).frame(width: 20, height: 3)
            }
        }
        .environment(\.colorScheme, palette.colorScheme)
        .accessibilityHidden(true)
    }

    private func tile(_ tint: Color, _ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(uiColor: palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(uiColor: palette.line)))
            .overlay(Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint))
            .frame(width: 22, height: 22)
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
