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

    var body: some View {
        NavigationStack {
            Form {
                clickingNote
                look
                feel
                screen
                macs
                fromMac
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
                    Text("iPhones cannot sense how hard you press, so a tap always clicks, even when tap to click is off on your Mac. Hold one finger still for half a second for a force click.")
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
            HStack(spacing: 12) {
                ForEach(ThemeChoice.allCases) { choice in
                    ThemeSwatch(choice: choice, selected: settings.theme == choice) {
                        settings.theme = choice
                    }
                }
            }
            .padding(.vertical, 6)
            Toggle("Show finger dots", isOn: $settings.showDots)
            Toggle(isOn: $settings.leftHanded) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Left-handed")
                    Text("Puts the main buttons on the left in Keys and Present.")
                        .font(.footnote).foregroundStyle(palette.inkSoftColor)
                }
            }
        }
        .listRowBackground(palette.raisedColor)
    }

    private var feel: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Haptic strength")
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
                    Image(systemName: "speaker.wave.3").foregroundStyle(palette.inkSoftColor).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            if !Haptics.shared.isSupported {
                Text("This device has no Taptic Engine, so there is nothing to feel.")
                    .font(.footnote).foregroundStyle(palette.inkSoftColor)
            }
        } header: {
            Text("Feel")
        } footer: {
            Text("Firmness follows Click on your Mac (\(session.trackpadSettings.clickPressure.title)). Haptics pause by themselves when the phone is warm.")
        }
        .listRowBackground(palette.raisedColor)
    }

    private var screen: some View {
        Section {
            Picker("Dim after", selection: $settings.dimDelay) {
                ForEach(PhoneSettings.dimDelayChoices, id: \.self) { delay in
                    Text(Self.durationText(delay)).tag(delay)
                }
            }
        } header: {
            Text("Screen")
        } footer: {
            Text("The trackpad dims when you stop touching it and wakes on the next touch. Glasspad keeps the screen on only while the trackpad is showing and never changes brightness.")
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
            Button {
                showPair = true
            } label: {
                Label("Pair a Mac", systemImage: "qrcode.viewfinder")
                    .foregroundStyle(palette.inkColor)
            }
            HStack {
                Text("This iPhone's name")
                Spacer()
                TextField("iPhone", text: $settings.phoneName)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(palette.inkSoftColor)
                    .submitLabel(.done)
                    .onSubmit { session.reconnect() }
            }
        } header: {
            Text("Macs")
        } footer: {
            Text(store.macs.isEmpty ? "No Mac paired yet." : "Swipe left on a Mac to forget it. The name above is what your Mac shows for this phone.")
        }
        .listRowBackground(palette.raisedColor)
    }

    @ViewBuilder private var fromMac: some View {
        if session.hasMacSettings {
            let s = session.trackpadSettings
            Section {
                LabeledContent("Tracking speed", value: String(format: "%.1f of 3", s.trackingSpeed))
                LabeledContent("Natural scrolling", value: s.naturalScrolling ? "On" : "Off")
                LabeledContent("Secondary click", value: s.secondaryClick.title)
                LabeledContent("Swipe between Spaces", value: s.swipeBetweenSpaces.title)
                LabeledContent("Mission Control", value: s.missionControl.title)
            } header: {
                Text("From your Mac")
            } footer: {
                Text("Gestures follow your Mac's own trackpad settings. Change them in System Settings on the Mac and the phone follows.")
            }
            .listRowBackground(palette.raisedColor)
        }
    }

    private var about: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.versionString)
            Link(destination: URL(string: "https://github.com/Soham109/glasspad")!) {
                HStack {
                    Text("Source code").foregroundStyle(palette.inkColor)
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(palette.inkSoftColor)
                }
            }
            Text("Glasspad is free and open source under the MIT license. It talks only to your paired Mac on your network: no accounts, no servers, no tracking. Every message is encrypted with a key only your Mac and this phone have.")
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
        seconds < 60 ? "\(Int(seconds)) seconds" : (seconds == 60 ? "1 minute" : "\(Int(seconds / 60)) minutes")
    }
}

private struct ThemeSwatch: View {
    @Environment(\.palette) private var palette
    let choice: ThemeChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    switch choice {
                    case .paper: swatch(.paper)
                    case .graphite: swatch(.graphite)
                    case .system:
                        HStack(spacing: 0) { swatch(.paper, corners: false); swatch(.graphite, corners: false) }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .frame(height: 64)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? palette.inkColor : palette.lineColor, lineWidth: selected ? 2 : 1)
                }
                Text(choice.title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? palette.inkColor : palette.inkSoftColor)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatch(_ p: Palette, corners: Bool = true) -> some View {
        RoundedRectangle(cornerRadius: corners ? 14 : 0, style: .continuous)
            .fill(Color(uiColor: p.background))
            .overlay { SoftDot(color: p.dot.withAlphaComponent(p.isDark ? 0.4 : 0.3), size: 22) }
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
