import Foundation

// The rules behind the phone's StandBy screens (Clock, Now Playing, Calendar): which clock
// face comes next, how the picture creeps to spare the screen, when the screen may stay on,
// and when night mode turns everything a dim red. The views live in the app.

/// The clock's faces. A tap moves to the next one.
public enum ClockFace: String, Codable, CaseIterable, Sendable {
    /// Big rounded numerals filling the pane.
    case digital
    /// A dial with hour numbers, two hands and a second hand.
    case analog
    /// Thin numerals and the date, the quietest face.
    case minimal

    public var next: ClockFace {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    public var title: String {
        switch self {
        case .digital: "Digital"
        case .analog: "Analog"
        case .minimal: "Minimal"
        }
    }
}

/// Hours and minutes as the clock draws them, 12 or 24 hour as the phone is set.
public enum ClockText {
    /// "9" and "41" at 9:41 in the morning; "21" and "41" in the evening on a 24 hour phone,
    /// "9" and "41" on a 12 hour one. A 24 hour clock keeps its leading zero ("09"), as iOS does.
    public static func parts(_ date: Date, uses24Hour: Bool, calendar: Calendar = .current) -> (hour: String, minute: String) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h24 = c.hour ?? 0
        let minute = String(format: "%02d", c.minute ?? 0)
        if uses24Hour { return (String(format: "%02d", h24), minute) }
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return (String(h12), minute)
    }

    /// Whether the phone shows time on a 24 hour clock (Settings > General > Date & Time).
    public static func uses24Hour(locale: Locale = .current) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        return !format.contains("a")
    }

    /// The hand angles in degrees clockwise from 12, for an analog face.
    public static func handAngles(_ date: Date, calendar: Calendar = .current) -> (hour: Double, minute: Double, second: Double) {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let s = Double(c.second ?? 0)
        let m = Double(c.minute ?? 0) + s / 60
        let h = Double((c.hour ?? 0) % 12) + m / 60
        return (h * 30, m * 6, s * 6)
    }
}

/// Spares an OLED screen from burn in: the whole picture moves a few points once a minute,
/// visiting nine spots around its resting place, one small step at a time.
public enum BurnInShift {
    /// The nine spots in visiting order, as multiples of the amplitude. Each is one step
    /// (sideways, up or down, or one diagonal) from the one before, including the wrap.
    static let path: [(Double, Double)] = [
        (0, 0), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1),
    ]

    /// Points to move the picture by at `date`. Changes only when the minute does.
    public static func offset(at date: Date, amplitude: Double = 3) -> (x: Double, y: Double) {
        let minute = Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down))
        let spot = path[((minute % path.count) + path.count) % path.count]
        return (spot.0 * amplitude, spot.1 * amplitude)
    }
}

/// Whether a StandBy screen may keep the phone awake, how bright it draws, and whether it
/// ticks every second. These screens are meant to stay up for hours on a desk or a nightstand,
/// so they are careful with the battery and the screen.
public struct StandByPower: Equatable, Sendable {
    /// Turn off auto-lock while this shows.
    public var keepsScreenOn: Bool
    /// 0...1, how bright the content draws on its black background.
    public var brightness: Double
    /// The analog face's second hand moves (otherwise the clock changes once a minute).
    public var ticksSeconds: Bool

    /// - Parameters:
    ///   - visible: a StandBy screen is on screen and the app is in front.
    ///   - charging: plugged in (charging or full).
    ///   - keepOnUnplugged: the person chose to keep the screen on without power too.
    ///   - lowPower: Low Power Mode is on.
    ///   - heat: the phone's thermal state, the same model the rest of the app uses.
    public init(visible: Bool, charging: Bool, keepOnUnplugged: Bool, lowPower: Bool, heat: PowerPolicy.Heat) {
        // On power the screen stays on, like StandBy. On battery only when asked, never in
        // Low Power Mode. Never once the phone is warm (`PowerPolicy.isWarm`): charging with
        // the screen on keeps it warm, which is hard on the battery.
        keepsScreenOn = visible && !PowerPolicy(heat: heat).isWarm && (charging || (keepOnUnplugged && !lowPower))
        var level = 1.0
        if lowPower { level = min(level, 0.75) }
        switch heat {
        case .nominal, .fair: break
        case .serious: level = min(level, 0.6)
        case .critical: level = min(level, 0.45)
        }
        brightness = level
        ticksSeconds = !lowPower && heat < .serious
    }
}

/// When night mode turns the StandBy screens a dim red.
public enum NightMode: String, Codable, CaseIterable, Sendable {
    case off
    /// From 10 PM to 7 AM. Apps cannot read the light sensor, so the time stands in for the dark.
    case atNight
    case always

    public static let startHour = 22
    public static let endHour = 7

    public var title: String {
        switch self {
        case .off: "Off"
        case .atNight: "At Night"
        case .always: "Always"
        }
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .off: return false
        case .always: return true
        case .atNight:
            let hour = calendar.component(.hour, from: date)
            return hour >= Self.startHour || hour < Self.endHour
        }
    }
}

/// What the Calendar screen shows: the event on now or next, then a few after it.
public struct UpNextEvent: Equatable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool

    public init(id: String, title: String, start: Date, end: Date, allDay: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
    }

    public enum Timing: Equatable, Sendable {
        /// On now, with this many whole minutes left (at least 1).
        case now(minutesLeft: Int)
        /// Starts within the hour, in this many minutes (at least 1).
        case soon(minutes: Int)
        /// Starts later.
        case later
    }

    public func timing(at now: Date) -> Timing {
        if start <= now { return .now(minutesLeft: max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))) }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 60 ? .soon(minutes: max(1, minutes)) : .later
    }

    /// Events not over yet, timed ones first in start order, then all-day ones. At most `limit`.
    public static func upcoming(_ events: [UpNextEvent], at now: Date, limit: Int = 3) -> [UpNextEvent] {
        let open = events.filter { $0.end > now }
        let timed = open.filter { !$0.allDay }.sorted { ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title) }
        let allDay = open.filter(\.allDay).sorted { $0.title < $1.title }
        return Array((timed + allDay).prefix(limit))
    }
}
