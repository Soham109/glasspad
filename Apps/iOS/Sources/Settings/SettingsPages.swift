import SwiftUI
import GlasspadKit

// The pages Settings links to: finger dots, haptic types, modes, and each mode's options.

/// Size, opacity and look of the dot under each finger, with a live preview.
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
                Toggle("Show Finger Dots", isOn: $settings.showDots)
            }
            .listRowBackground(palette.raisedColor)
            if settings.showDots {
                Section("Style") {
                    Picker("Style", selection: $settings.dotStyle) {
                        ForEach(DotStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    slider("Size", value: $settings.dotSize, range: PhoneSettings.dotSizeRange,
                           text: "\(Int(settings.dotSize)) pt", low: "circle.fill", high: "circle.fill", lowScale: 0.6)
                    slider("Opacity", value: $settings.dotOpacity, range: PhoneSettings.dotOpacityRange,
                           text: settings.dotOpacity.formatted(.percent.precision(.fractionLength(0))),
                           low: "circle.dotted", high: "circle.fill", lowScale: 1)
                    Button("Use Defaults") {
                        settings.dotStyle = .soft
                        settings.dotSize = 44
                        settings.dotOpacity = 1
                    }
                }
                .listRowBackground(palette.raisedColor)
            }
        }
        .scrollContentBackground(.hidden)
        .background(SurfaceBackground())
        .navigationTitle("Finger Dots")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String,
                        low: String, high: String, lowScale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(text).monospacedDigit().foregroundStyle(palette.inkSoftColor)
            }
            HStack(spacing: 12) {
                Image(systemName: low).scaleEffect(lowScale).foregroundStyle(palette.inkSoftColor).accessibilityHidden(true)
                Slider(value: value, in: range).accessibilityLabel(title).accessibilityValue(text)
                Image(systemName: high).foregroundStyle(palette.inkSoftColor).accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
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

/// Every haptic in one place: overall strength, the trackpad's own, and which kinds play.
struct HapticsSettings: View {
    @Environment(\.palette) private var palette
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.1").foregroundStyle(palette.inkSoftColor).accessibilityHidden(true)
                    Slider(value: $settings.hapticStrength, in: 0...1) { editing in
                        if !editing {
                            session.refreshHapticStrength()
                            Haptics.shared.play(.click)
                        }
                    }
                    .accessibilityLabel("Strength")
                    .accessibilityValue(settings.hapticStrength.formatted(.percent.precision(.fractionLength(0))))
                    Image(systemName: "speaker.wave.3").foregroundStyle(palette.inkSoftColor).accessibilityHidden(true)
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
                ForEach(HapticChannel.allCases) { channel in
                    Toggle(isOn: Binding(get: { !settings.hapticsOff.contains(channel) },
                                         set: { on in
                                             settings.setHaptic(channel, on: on)
                                             if on { Haptics.shared.play(channel.cue) }
                                         })) {
                        Label(channel.title, systemImage: channel.symbol)
                    }
                }
            } header: {
                Text("Everywhere in Glasspad")
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

/// Show, hide and reorder modes; split Actions back into its four tools.
struct ModesSettings: View {
    @Environment(\.palette) private var palette
    @Bindable var settings = PhoneSettings.shared

    private var listed: [AppMode] {
        let split = settings.modeList.splitActions
        let names = settings.modeList.order.filter { AppMode(rawValue: $0) != nil }
            + AppMode.allCases.map(\.rawValue).filter { !settings.modeList.order.contains($0) }
        return names.compactMap(AppMode.init(rawValue:)).filter { mode in
            if mode == .actions { return !split }
            if ModeListLayout.actionParts.contains(mode.rawValue) { return split }
            return true
        }
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
                Text("Shown in the Mode Pill")
            } footer: {
                Text("Drag to reorder. Trackpad is always there.")
            }
            .listRowBackground(palette.raisedColor)
            Section {
                Toggle(isOn: $settings.modeList.splitActions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Separate Deck, Macros, Clipboard and Present")
                        Text("Shows them as four modes instead of one Actions mode. Nothing is lost either way.")
                            .font(.footnote).foregroundStyle(palette.inkSoftColor)
                    }
                }
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
        case .dock, .keys, .actions, .deck, .present: true
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
            case .keys:
                Section {
                    Toggle("Shortcut Row", isOn: $settings.keysShowsShortcuts)
                } footer: {
                    Text("Copy, Paste, Undo and more, in a row above the arrow keys.")
                }
                .listRowBackground(palette.raisedColor)
            case .actions, .deck: actions
            case .present:
                Section {
                    Toggle("Start Timer on First Next", isOn: $settings.presentStartsTimer)
                }
                .listRowBackground(palette.raisedColor)
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
            Text("Touch and hold an app in Dock to keep, hide or move it. Your Mac's Dock stays as it is.")
        }
        .listRowBackground(palette.raisedColor)
        if !settings.dockArrangement.order.isEmpty || !settings.dockArrangement.hidden.isEmpty {
            Section {
                if !settings.dockArrangement.order.isEmpty {
                    Button("Use the Mac's Order") { settings.dockArrangement.order = [] }
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
            Toggle("Hide Mac Dock", isOn: macDock(\.hidden))
            Toggle("Hide Mac Dock While Connected", isOn: macDock(\.hideWhileConnected))
        } header: {
            Text("Your Mac's Dock")
        } footer: {
            Text(session.isConnected
                 ? "Your Dock settings come back as they were when you turn this off, disconnect or quit Glasspad."
                 : "Connect to your Mac to change these.")
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

    private func macDock(_ key: WritableKeyPath<MacDockState, Bool>) -> Binding<Bool> {
        Binding {
            session.macDockState?[keyPath: key] ?? false
        } set: { on in
            var s = session.macDockState ?? MacDockState(hidden: false, hideWhileConnected: false)
            s[keyPath: key] = on
            session.setMacDock(s)
        }
    }
}
