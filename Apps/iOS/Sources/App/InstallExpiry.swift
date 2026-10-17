import Foundation
import GlasspadKit
import Observation

/// When this install stops opening. With a free Apple account Xcode's profile lasts 7 days and
/// the Mac renews it over Wi-Fi; Settings > About shows the date, and the mode menu says it
/// once on the last day. Nil without a profile (the simulator, App Store builds).
@MainActor
@Observable
final class InstallExpiry {
    static let shared = InstallExpiry()

    /// Read from the app's embedded profile the first time anything asks, off the main thread.
    var date: Date? {
        if !started { start() }
        return loaded
    }

    private var loaded: Date?
    @ObservationIgnored private var started = false

    private init() {
        #if DEBUG
        // -GPExpiry <ISO 8601 date, or +<hours>h from now>: pretend the install ends then (screenshots).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-GPExpiry"), i + 1 < args.count {
            let text = args[i + 1]
            let hours = text.hasPrefix("+") && text.hasSuffix("h") ? Double(text.dropFirst().dropLast()) : nil
            guard let fake = hours.map({ Date(timeIntervalSinceNow: $0 * 3600) }) ?? ISO8601DateFormatter().date(from: text) else { return }
            loaded = fake
            started = true
        }
        #endif
    }

    /// Within this long of the end, it is the last day.
    static let lastDay: TimeInterval = 24 * 3600

    func isLastDay(now: Date = Date()) -> Bool {
        guard let date else { return false }
        return date > now && date.timeIntervalSince(now) <= Self.lastDay
    }

    /// The mode menu's one line on the last day: "Glasspad works until 3:10 PM tomorrow. ..."
    func lastDayLine(now: Date = Date()) -> String? {
        guard isLastDay(now: now), let date else { return nil }
        let day = Calendar.current.isDate(date, inSameDayAs: now) ? "today" : "tomorrow"
        return "Glasspad works until \(date.formatted(date: .omitted, time: .shortened)) \(day). Keep this iPhone on your Mac's Wi-Fi."
    }

    private func start() {
        started = true
        Task.detached(priority: .utility) {
            let date = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap(ProvisionExpiry.expirationDate(fromProvision:))
            await MainActor.run { InstallExpiry.shared.loaded = date }
        }
    }
}
