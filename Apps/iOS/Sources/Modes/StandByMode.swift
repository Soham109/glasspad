import GlasspadKit
import Observation
import SwiftUI
import UIKit

// The StandBy screens: Clock, Now Playing and Calendar. Like StandBy on iPhone they are made
// to stay up for hours next to the Mac or on a nightstand, so they draw calm grey on black
// (black pixels are off on OLED), move a few points every minute against burn in, change at
// most once a second, and keep the phone awake only on power unless asked. Night mode turns
// all of it a dim red. The rules live in GlasspadKit (StandBy.swift); this file holds what
// the three screens share.

// MARK: - Colours

/// StandBy's colours. These screens stay dark in every theme, as StandBy does: a bright
/// background held for hours costs battery and marks the screen. Night red is applied over
/// the whole picture by `StandByScreen`, so views only ever draw these greys.
struct StandByStyle {
    /// Mono: no colour, accents draw in the primary grey.
    let monochrome: Bool
    private let good: Color

    init(_ palette: Palette) {
        monochrome = palette.monochrome
        // The dark green whatever the theme: a light theme's deeper green would sink into black.
        good = Palette.graphite.good
    }

    static let backgroundColor = Color(uiColor: .black)
    /// Numerals and titles: a soft grey, never full white.
    let primary = Color(uiColor: UIColor(white: 0.84, alpha: 1))
    let secondary = Color(uiColor: UIColor(white: 0.52, alpha: 1))
    let faint = Color(uiColor: UIColor(white: 0.24, alpha: 1))
    /// Fills behind buttons and empty artwork.
    let fill = Color(uiColor: UIColor(white: 0.11, alpha: 1))

    /// The analog second hand.
    var hand: Color { monochrome ? primary : Color(uiColor: UIColor(hex: 0xE8900C)) }
    /// The weekday on the calendar, like the Calendar app's red.
    var weekday: Color { monochrome ? primary : Color(uiColor: UIColor(hex: 0xE5483E)) }
    /// The charging bolt. Mono's "good" is its ink, which could be black; the grey reads on black.
    var charge: Color { monochrome ? secondary : good }

    /// What night mode multiplies every grey by: StandBy's dim red.
    static let nightRed = Color(uiColor: UIColor(hex: 0xC8261A))
}

// MARK: - Settings

/// The StandBy screens' own choices, kept on the phone.
@MainActor
@Observable
final class StandBySettings {
    static let shared = StandBySettings()

    var face: ClockFace { didSet { defaults.set(face.rawValue, forKey: Key.face) } }
    var nightMode: NightMode { didSet { defaults.set(nightMode.rawValue, forKey: Key.night) } }
    /// Keep the screen on without power too (never in Low Power Mode).
    var keepOnUnplugged: Bool {
        didSet {
            defaults.set(keepOnUnplugged, forKey: Key.keepOn)
            ScreenAwake.update()
        }
    }

    private let defaults: UserDefaults
    private enum Key {
        static let face = "standByFace", night = "standByNight", keepOn = "standByKeepOnUnplugged"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        face = ClockFace(rawValue: defaults.string(forKey: Key.face) ?? "") ?? .digital
        nightMode = NightMode(rawValue: defaults.string(forKey: Key.night) ?? "") ?? .atNight
        keepOnUnplugged = defaults.bool(forKey: Key.keepOn)
    }
}

// MARK: - Power

/// Watches power, Low Power Mode and heat, only while a StandBy screen is on screen, and
/// decides with `StandByPower` whether it keeps the phone awake and how bright it draws.
@MainActor
@Observable
final class StandByMonitor {
    static let shared = StandByMonitor()

    private(set) var charging = false
    /// 0...1, or nil when iOS does not know (the simulator).
    private(set) var batteryLevel: Double?
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var heat = PowerMonitor.heat(ProcessInfo.processInfo.thermalState)
    /// StandBy screens on screen right now (a layout can show two).
    private(set) var visibleCount = 0

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    #if DEBUG
    @ObservationIgnored private var demoLevel: Double?
    #endif

    var power: StandByPower {
        StandByPower(visible: visibleCount > 0, charging: charging, keepOnUnplugged: StandBySettings.shared.keepOnUnplugged,
                     lowPower: lowPower, heat: heat)
    }

    func appeared() {
        visibleCount += 1
        if visibleCount == 1 { start() }
        ScreenAwake.update()
    }

    func disappeared() {
        visibleCount = max(0, visibleCount - 1)
        if visibleCount == 0 { stop() }
        ScreenAwake.update()
    }

    private func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [UIDevice.batteryStateDidChangeNotification, UIDevice.batteryLevelDidChangeNotification,
                                          .NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { StandByMonitor.shared.refresh() }
            }
        }
    }

    private func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private func refresh() {
        let device = UIDevice.current
        var plugged = device.batteryState == .charging || device.batteryState == .full
        #if DEBUG
        if demoLevel != nil { plugged = true }
        #endif
        var level = device.batteryLevel < 0 ? nil : Double(device.batteryLevel)
        #if DEBUG
        if let demoLevel { level = demoLevel }
        #endif
        let saving = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = PowerMonitor.heat(ProcessInfo.processInfo.thermalState)
        let before = power.keepsScreenOn
        if charging != plugged { charging = plugged }
        if batteryLevel != level { batteryLevel = level }
        if lowPower != saving { lowPower = saving }
        if heat != thermal { heat = thermal }
        if power.keepsScreenOn != before { ScreenAwake.update() }
    }

    #if DEBUG
    /// `-GPStandByCharging <percent>`: pretend to be plugged in, for screenshots.
    func applyDemo(level: Double) {
        demoLevel = level
        refresh()
    }
    #endif
}

// MARK: - Screen

/// What every StandBy screen sits in: black edge to edge, the picture moved a few points each
/// minute, dimmed when the phone saves power or runs warm, and red in night mode.
struct StandByScreen<Content: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var settings = StandBySettings.shared
    var monitor = StandByMonitor.shared
    let content: (_ minute: Date, _ style: StandByStyle) -> Content
    /// Room kept for the mode pill, on the edge it sits on, when this screen reaches that edge.
    @State private var pillRoom = EdgeInsets()

    init(@ViewBuilder content: @escaping (_ minute: Date, _ style: StandByStyle) -> Content) {
        self.content = content
        #if DEBUG
        StandByDemo.apply()
        #endif
    }

    var body: some View {
        // Read here, outside the timeline, so a change redraws at once and not at the next minute.
        let nightMode = settings.nightMode
        let brightness = monitor.power.brightness
        let style = StandByStyle(palette)
        TimelineView(.everyMinute) { context in
            let date = standByTime(context.date)
            let night = nightMode.isActive(at: date)
            let shift = BurnInShift.offset(at: date)
            // Night mode is dimmer on top of any power or heat dimming.
            let level = brightness * (night ? 0.8 : 1)
            content(date, style)
                .offset(x: shift.x, y: shift.y)
                .animation(reduceMotion ? nil : .easeInOut(duration: 2), value: shift.x + shift.y * 10)
                .grayscale(night ? 1 : 0)
                .colorMultiply(night ? StandByStyle.nightRed : .white)
                .opacity(level)
                .animation(.easeInOut(duration: 1.2), value: night)
        }
        .padding(pillRoom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StandByStyle.backgroundColor.ignoresSafeArea())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pillRoom = Self.pillRoom(for: $0) }
        .environment(\.colorScheme, .dark)
        .onAppear { monitor.appeared() }
        .onDisappear { monitor.disappeared() }
    }

    /// The pill floats just inside the safe area at the top (or bottom) of the screen. A
    /// screen that reaches that edge keeps the pill's height clear, so nothing sits under it.
    private static func pillRoom(for frame: CGRect) -> EdgeInsets {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return EdgeInsets() }
        let safe = window.safeAreaInsets
        let room: CGFloat = 46
        if PhoneSettings.shared.pillPosition == .bottom {
            return EdgeInsets(top: 0, leading: 0, bottom: frame.maxY >= window.bounds.height - safe.bottom - 1 ? room : 0, trailing: 0)
        }
        return EdgeInsets(top: frame.minY <= safe.top + 1 ? room : 0, leading: 0, bottom: 0, trailing: 0)
    }
}

/// The choices every StandBy screen offers when touched and held.
struct StandByMenu: View {
    @Bindable var settings = StandBySettings.shared
    var showsFaces = false

    var body: some View {
        if showsFaces {
            Picker("Clock Face", selection: $settings.face) {
                ForEach(ClockFace.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        Picker(selection: $settings.nightMode) {
            ForEach(NightMode.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            Label("Night Mode", systemImage: "moon")
        }
        .pickerStyle(.menu)
        Toggle(isOn: $settings.keepOnUnplugged) {
            Label("Stay On When Unplugged", systemImage: "bolt.slash")
        }
    }
}

/// StandBy's options on a mode's page in Settings.
struct StandBySettingsSections: View {
    @Environment(\.palette) private var palette
    @Bindable var settings = StandBySettings.shared

    var body: some View {
        Section {
            Picker("Clock Face", selection: $settings.face) {
                ForEach(ClockFace.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } footer: {
            Text("Tap the clock to change its face.")
        }
        .listRowBackground(palette.raisedColor)
        Section {
            Picker("Night Mode", selection: $settings.nightMode) {
                ForEach(NightMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } footer: {
            Text("At Night turns the screen a dim red from \(Self.hour(NightMode.startHour)) to \(Self.hour(NightMode.endHour)).")
        }
        .listRowBackground(palette.raisedColor)
        Section {
            Toggle("Stay On When Unplugged", isOn: $settings.keepOnUnplugged)
        } footer: {
            Text("The screen stays on while your iPhone charges. This keeps it on with the battery too, except in Low Power Mode.")
        }
        .listRowBackground(palette.raisedColor)
    }

    /// "10 PM", or "22:00" on a 24 hour phone.
    private static func hour(_ h: Int) -> String {
        let date = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

// MARK: - Type

/// Exact sizes for text that has to fill a pane: how wide a string is and how tall its
/// capitals are, per point of font size, in the font the view draws with.
enum StandByType {
    struct Metrics {
        /// Width of the string per point of font size.
        let width: CGFloat
        let capHeight: CGFloat
        /// The height SwiftUI gives one line, per point.
        let lineHeight: CGFloat
    }

    static func font(_ size: CGFloat, weight: UIFont.Weight, rounded: Bool) -> UIFont {
        var descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if rounded, let r = descriptor.withDesign(.rounded) { descriptor = r }
        // Monospaced digits, so the clock does not shift as the minutes change.
        descriptor = descriptor.addingAttributes([.featureSettings: [[
            UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
            UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
        ]]])
        return UIFont(descriptor: descriptor, size: size)
    }

    static func metrics(_ text: String, weight: UIFont.Weight, rounded: Bool) -> Metrics {
        let f = font(100, weight: weight, rounded: rounded)
        let w = (text as NSString).size(withAttributes: [.font: f]).width
        return Metrics(width: w / 100, capHeight: f.capHeight / 100, lineHeight: f.lineHeight / 100)
    }

    static func swiftUI(_ size: CGFloat, weight: Font.Weight, rounded: Bool) -> Font {
        .system(size: size, weight: weight, design: rounded ? .rounded : .default).monospacedDigit()
    }
}

/// The time StandBy screens show for a timeline date. The real time, except in debug builds
/// started with `-GPStandByTime`.
func standByTime(_ date: Date) -> Date {
    #if DEBUG
    date.addingTimeInterval(StandByDemo.timeOffset)
    #else
    date
    #endif
}

#if DEBUG
/// Debug builds only, for screenshots: `-GPStandByCharging <percent>` pretends to charge,
/// `-GPStandByNight <off|atNight|always>` and `-GPStandByFace <digital|analog|minimal>` set
/// those choices, `-GPStandByTime <HH:mm>` starts the clock at that time, and
/// `-GPStandByDemo` fills Calendar with sample events.
enum StandByDemo {
    @MainActor private static var applied = false
    nonisolated(unsafe) static var timeOffset: TimeInterval = 0

    @MainActor static func apply() {
        guard !applied else { return }
        applied = true
        if let level = value("-GPStandByCharging").flatMap(Double.init) {
            StandByMonitor.shared.applyDemo(level: level / 100)
        }
        if let night = value("-GPStandByNight").flatMap(NightMode.init(rawValue:)) { StandBySettings.shared.nightMode = night }
        if let face = value("-GPStandByFace").flatMap(ClockFace.init(rawValue:)) { StandBySettings.shared.face = face }
        if let time = value("-GPStandByTime") {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            let now = Date()
            if parts.count == 2, let target = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now) {
                // Whole minutes, so the shown minute still turns over with the real one.
                let minute = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
                timeOffset = target.timeIntervalSince(minute)
            }
        }
    }

    static var showsSampleEvents: Bool { ProcessInfo.processInfo.arguments.contains("-GPStandByDemo") }

    private static func value(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }
}
#endif
