import EventKit
import GlasspadKit
import Observation
import SwiftUI
import UIKit

/// The Calendar StandBy screen: today's date the way the Calendar app's icon shows it, then
/// the event on now or next and the two after it, from the phone's own calendars. It asks
/// for calendar access only when someone opens it, and only after a tap.
struct CalendarMode: View {
    var feed = CalendarFeed.shared

    var body: some View {
        StandByScreen { minute, style in
            GeometryReader { geo in
                content(minute, style, geo.size)
            }
        }
        .contextMenu { StandByMenu() }
        .onAppear { feed.start() }
        .onDisappear { feed.stop() }
    }

    @ViewBuilder private func content(_ now: Date, _ style: StandByStyle, _ size: CGSize) -> some View {
        let pad = CGSize(width: max(18, size.width * 0.08), height: max(18, size.height * 0.09))
        let room = CGSize(width: size.width - pad.width * 2, height: size.height - pad.height * 2)
        let scale = min(room.width, room.height * 1.1)
        let wide = room.width > room.height * 1.5
        let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: scale * 0.12))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: scale * 0.07))
        // Wide: the date and the events side by side, centred together. Otherwise one above
        // the other along the left edge, like the Calendar widget.
        layout {
            DateTile(date: now, style: style, scale: scale)
            agenda(now, style, scale: scale, rows: wide || room.height > scale * 1.1 ? 3 : 2)
                .frame(maxWidth: wide ? room.width * 0.58 : .infinity, alignment: .leading)
        }
        .frame(width: room.width, alignment: wide ? .center : .leading)
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder private func agenda(_ now: Date, _ style: StandByStyle, scale: CGFloat, rows: Int) -> some View {
        let titleSize = min(26, max(15, scale * 0.072))
        switch feed.access {
        case .allowed:
            let events = UpNextEvent.upcoming(feed.events, at: now, limit: rows)
            if events.isEmpty {
                Text("No upcoming events")
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(style.secondary)
            } else {
                VStack(alignment: .leading, spacing: titleSize * 0.85) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        EventRow(event: event, now: now, color: feed.colors[event.id], style: style,
                                 titleSize: index == 0 ? titleSize : titleSize * 0.84)
                    }
                }
            }
        case .notAsked:
            VStack(alignment: .leading, spacing: titleSize * 0.7) {
                Text("See your next events here.")
                    .font(.system(size: titleSize * 0.84, weight: .medium))
                    .foregroundStyle(style.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                StandByButton(title: "Allow Calendar", size: titleSize * 0.8, style: style) { feed.requestAccess() }
            }
        case .denied:
            VStack(alignment: .leading, spacing: titleSize * 0.7) {
                Text("To see your events here, allow Glasspad to read your calendar in Settings.")
                    .font(.system(size: titleSize * 0.84, weight: .medium))
                    .foregroundStyle(style.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                StandByButton(title: "Open Settings", size: titleSize * 0.8, style: style) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
    }
}

/// The weekday in red over the day of the month, like the Calendar app's icon.
private struct DateTile: View {
    let date: Date
    let style: StandByStyle
    let scale: CGFloat

    var body: some View {
        let daySize = min(110, max(40, scale * 0.3))
        VStack(alignment: .leading, spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.system(size: daySize * 0.24, weight: .semibold))
                .tracking(daySize * 0.01)
                .foregroundStyle(style.weekday)
            Text(date.formatted(.dateTime.day()))
                .font(StandByType.swiftUI(daySize, weight: .regular, rounded: false))
                .foregroundStyle(style.primary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// One event: a line in its calendar's colour, the title, and when.
private struct EventRow: View {
    let event: UpNextEvent
    let now: Date
    let color: Color?
    let style: StandByStyle
    let titleSize: CGFloat

    var body: some View {
        HStack(spacing: titleSize * 0.55) {
            Capsule()
                .fill(style.monochrome ? style.secondary : (color ?? style.secondary))
                .frame(width: max(3, titleSize * 0.17))
            VStack(alignment: .leading, spacing: titleSize * 0.12) {
                Text(event.title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(style.primary)
                Text(when)
                    .font(.system(size: titleSize * 0.78, weight: .medium).monospacedDigit())
                    .foregroundStyle(style.secondary)
            }
            .lineLimit(1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var when: String {
        if event.allDay { return "All day" }
        let time = event.start.formatted(date: .omitted, time: .shortened)
        switch event.timing(at: now) {
        case .now(let left): return left == 1 ? "Now, 1 minute left" : "Now, \(left) minutes left"
        case .soon(let minutes): return minutes == 1 ? "In 1 minute" : "In \(minutes) minutes"
        case .later:
            return Calendar.current.isDateInToday(event.start) ? time : "Tomorrow at \(time)"
        }
    }
}

/// A quiet capsule button on black.
struct StandByButton: View {
    let title: String
    let size: CGFloat
    let style: StandByStyle
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(style.primary)
                .padding(.horizontal, size * 1.1)
                .padding(.vertical, size * 0.6)
                .frame(minHeight: 44)
                .background(Capsule().fill(style.fill))
                .contentShape(Capsule())
        }
        .buttonStyle(TileStyle())
    }
}

// MARK: - Events

/// Events from the phone's calendars for the next day, kept fresh while Calendar is on screen.
@MainActor
@Observable
final class CalendarFeed {
    static let shared = CalendarFeed()

    enum Access { case notAsked, allowed, denied }

    private(set) var access: Access = CalendarFeed.currentAccess
    private(set) var events: [UpNextEvent] = []
    /// Each event's calendar colour, by event id.
    private(set) var colors: [String: Color] = [:]

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var running = 0

    private static var currentAccess: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    func start() {
        running += 1
        guard running == 1 else { return }
        #if DEBUG
        if StandByDemo.showsSampleEvents { return applyDemo() }
        #endif
        access = Self.currentAccess
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarFeed.shared.reload() }
        }
        reload()
        // A new day, or events that crept into the next 24 hours: look again every 15 minutes.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                self?.reload()
            }
        }
    }

    func stop() {
        running = max(0, running - 1)
        guard running == 0 else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            access = Self.currentAccess
            reload()
        }
    }

    private func reload() {
        #if DEBUG
        if StandByDemo.showsSampleEvents { return }
        #endif
        access = Self.currentAccess
        guard access == .allowed else {
            events = []
            return
        }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(86_400), calendars: nil)
        let found = store.events(matching: predicate)
            // Declined invitations are not plans.
            .filter { event in !(event.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined } }
        events = found.map { UpNextEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Event",
                                         start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay) }
        colors = Dictionary(found.map { ($0.eventIdentifier ?? "", Color(cgColor: $0.calendar.cgColor)) },
                            uniquingKeysWith: { a, _ in a })
    }

    #if DEBUG
    private func applyDemo() {
        access = .allowed
        // On the hour and half hour around the time shown, as real events are.
        let now = standByTime(Date())
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        func at(_ minutes: Double) -> Date { hour.addingTimeInterval(minutes * 60) }
        events = [
            UpNextEvent(id: "1", title: "Design review", start: at(0), end: at(45)),
            UpNextEvent(id: "2", title: "Lunch with Maya", start: at(120), end: at(180)),
            UpNextEvent(id: "3", title: "Call with the studio", start: at(270), end: at(300)),
        ]
        colors = ["1": Color(uiColor: .systemOrange), "2": Color(uiColor: .systemGreen), "3": Color(uiColor: .systemBlue)]
    }
    #endif
}
