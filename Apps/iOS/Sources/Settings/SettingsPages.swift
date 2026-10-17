import SwiftUI
import GlasspadKit

// The pages Settings links to: finger dots, haptic types, modes, and each mode's options.

/// The dot under each finger: on or off, and its size, with a live preview.
struct FingerDotSettings: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Bindable var settings = PhoneSettings.shared

    var body: some View {
        Form {
            Section {
                let p = settings.theme.resolved(scheme).customized(settings)
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: p.background))
                    if settings.showDots {
                        HStack(spacing: p.dotDiameter * 0.9) {
                            FingerDotPreview(palette: p)
                            FingerDotPreview(palette: p)
                        }
                    } else {
                        Text("Dots are off").font(.subheadline).foregroundStyle(Color(uiColor: p.inkSoft))
                    }
                }
                .frame(height: 150)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .accessibilityLabel("Preview")
                .animation(.snappy, value: settings.dotSizeChoice)
                Toggle("Show Finger Dots", isOn: $settings.showDots)
                if settings.showDots {
                    Picker("Size", selection: $settings.dotSizeChoice) {
                        ForEach(DotSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                Text("A dot follows each finger on the trackpad, so you can see where you touch.")
            }
            .listRowBackground(palette.raisedColor)
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .navigationTitle("Finger Dots")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: settings.showDots)
    }
}

/// One finger dot drawn the way the trackpad draws it.
struct FingerDotPreview: View {
    let palette: Palette
    var body: some View {
        let d = palette.dotDiameter
        let c = Color(uiColor: palette.dot)
        switch palette.dotStyle {
        case .soft:
            Circle()
                .fill(RadialGradient(colors: [c, c.opacity(0.85), c.opacity(0)], center: .center, startRadius: 0, endRadius: d / 2))
                .frame(width: d, height: d)
        case .solid:
            Circle().fill(c).frame(width: d * 0.8, height: d * 0.8)
        case .ring:
            Circle().strokeBorder(c, lineWidth: max(2, d * 0.07)).frame(width: d, height: d)
        }
    }
}

/// Pointer speed, acceleration, scrolling, and the trackpad settings that come from the Mac.
struct PointerSettings: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared

    var body: some View {
        Form {
            TrackpadTuningSection(part: .motion)
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .navigationTitle("Pointer and Scrolling")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Every haptic in one place: overall strength, the trackpad's own per kind, and switches for
/// the rest.
struct HapticsSettings: View {
    @Environment(\.palette) private var palette
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    // A still iPhone to a buzzing one: a vibration scale, not a volume one.
                    Image(systemName: "iphone.gen3").foregroundStyle(palette.inkSoftColor).accessibilityHidden(true)
                    Slider(value: $settings.hapticStrength, in: 0...1) { editing in
                        if !editing {
                            session.refreshHapticStrength()
                            Haptics.shared.play(.click)
                        }
                    }
                    .accessibilityLabel("Strength")
                    .accessibilityValue(settings.hapticStrength.formatted(.percent.precision(.fractionLength(0))))
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right").foregroundStyle(palette.inkSoftColor).accessibilityHidden(true)
                }
            } header: {
                Text("Strength")
            } footer: {
                if Haptics.shared.isSupported {
                    Text("Also follows Click on your Mac, set to \(session.trackpadSettings.clickPressure.title).")
                } else {
                    Text("This iPhone has no Taptic Engine, so there is nothing to feel.")
                }
            }
            .listRowBackground(palette.raisedColor)
            TrackpadTuningSection(part: .haptics)
            Section {
                // Clicks and Force Click are the sliders above: at 0 they are off.
                ForEach(HapticChannel.allCases.filter { !PhoneSettings.slidersCoverHaptics.contains($0) }) { channel in
                    Toggle(isOn: Binding(get: { !settings.hapticsOff.contains(channel) },
                                         set: { on in
                                             settings.setHaptic(channel, on: on)
                                             if on { Haptics.shared.play(channel.cue) }
                                         })) {
                        Label(channel.title, systemImage: channel.symbol)
                    }
                }
            } header: {
                Text("Elsewhere in Glasspad")
            }
            .listRowBackground(palette.raisedColor)
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .navigationTitle("Haptics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension HapticChannel {
    var cue: HapticCue {
        switch self {
        case .click, .buttons: .click
        case .forceClick: .forceClickRamp
        case .detent: .detent
        case .snap: .snap
        case .error: .error
        }
    }
}

/// Show, hide and reorder modes.
struct ModesSettings: View {
    @Environment(\.palette) private var palette
    @Bindable var settings = PhoneSettings.shared

    private var listed: [AppMode] {
        let names = settings.modeList.order.filter { AppMode(rawValue: $0) != nil }
            + AppMode.allCases.map(\.rawValue).filter { !settings.modeList.order.contains($0) }
        return names.compactMap(AppMode.init(rawValue:)).filter { !ModeListLayout.actionParts.contains($0.rawValue) }
    }

    var body: some View {
        Form {
            Section {
                ForEach(listed) { mode in
                    HStack(spacing: 12) {
                        Image(systemName: mode.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(mode == .trackpad ? Color.gray : mode.accent(palette),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mode.title)
                            Text(mode.blurb).font(.footnote).foregroundStyle(palette.inkSoftColor).lineLimit(2)
                        }
                        Spacer()
                        if mode != .trackpad {
                            Toggle(mode.title, isOn: Binding(get: { !settings.modeList.hidden.contains(mode.rawValue) },
                                                             set: { on in
                                                                 if on { settings.modeList.hidden.remove(mode.rawValue) }
                                                                 else { settings.modeList.hidden.insert(mode.rawValue) }
                                                             }))
                                .labelsHidden()
                        }
                    }
                }
                .onMove { from, to in
                    var names = listed.map(\.rawValue)
                    names.move(fromOffsets: from, toOffset: to)
                    let rest = settings.modeList.order.filter { !names.contains($0) }
                    settings.modeList.order = names + rest
                }
            } header: {
                Text("In the Mode Menu")
            } footer: {
                Text("Drag to reorder. Trackpad is always there.")
            }
            .listRowBackground(palette.raisedColor)
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .navigationTitle("Modes")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.modeList) {
            // If the screen showing now just disappeared, move to the mode standing in for it.
            let router = AppRouter.shared
            if router.mode.shown != router.mode { router.show(router.mode) }
        }
    }
}

extension AppMode {
    /// Modes with their own page in Settings.
    var hasSettings: Bool {
        switch self {
        case .dock, .actions, .deck, .present, .clock, .nowPlaying, .calendar: true
        default: false
        }
    }
}

/// One mode's options.
struct ModeDetailSettings: View {
    @Environment(\.palette) private var palette
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    let mode: AppMode

    var body: some View {
        Form {
            switch mode {
            case .dock: apps
            case .actions, .deck: actions
            case .present:
                Section {
                    Toggle("Start Timer on First Next", isOn: $settings.presentStartsTimer)
                }
                .listRowBackground(palette.raisedColor)
            case .clock, .nowPlaying, .calendar: StandBySettingsSections()
            default: EmptyView()
            }
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var apps: some View {
        Section {
            Picker("Icon Size", selection: $settings.dockDensity) {
                Text("Small").tag(DockDensity.compact)
                Text("Medium").tag(DockDensity.regular)
                Text("Large").tag(DockDensity.large)
            }
            .pickerStyle(.segmented)
            Toggle("Show Names", isOn: $settings.dockShowsNames)
        } header: {
            Text("Icons")
        } footer: {
            Text("Touch and hold an app in Dock to hide it or always show it. Your Mac's Dock stays as it is.")
        }
        .listRowBackground(palette.raisedColor)
        if !settings.dockArrangement.order.isEmpty || !settings.dockArrangement.hidden.isEmpty {
            Section {
                if !settings.dockArrangement.order.isEmpty {
                    Button("Use Mac Order") { settings.dockArrangement.order = [] }
                }
                if !settings.dockArrangement.hidden.isEmpty {
                    Button("Show \(settings.dockArrangement.hidden.count) Hidden \(settings.dockArrangement.hidden.count == 1 ? "App" : "Apps")") {
                        settings.dockArrangement.hidden = []
                    }
                }
            }
            .listRowBackground(palette.raisedColor)
        }
        Section {
            Picker("Hide Mac Dock", selection: macDockHiding) {
                ForEach(MacDockHiding.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Your Mac's Dock")
        } footer: {
            Text(session.isConnected
                 ? MacDockHiding.footer
                 : "Connect to your Mac to change this.")
        }
        .disabled(!session.isConnected)
        .listRowBackground(palette.raisedColor)
    }

    @ViewBuilder private var actions: some View {
        Section {
            Picker("Button Size", selection: $settings.deckTileScale) {
                Text("Small").tag(0.85)
                Text("Medium").tag(1.0)
                Text("Large").tag(1.3)
            }
            .pickerStyle(.segmented)
            Toggle("Show Labels", isOn: $settings.deckShowsTitles)
        } header: {
            Text("Button Size")
        } footer: {
            Text("The top of Actions follows the app in front on your Mac. Touch and hold a button to change it.")
        }
        .listRowBackground(palette.raisedColor)
        Section {
            Button("Show Tips Again") { settings.seenTips = [] }
        }
        .listRowBackground(palette.raisedColor)
    }

    private var macDockHiding: Binding<MacDockHiding> {
        Binding {
            MacDockHiding(session.macDockState)
        } set: { choice in
            session.setMacDock(choice.state)
        }
    }
}
