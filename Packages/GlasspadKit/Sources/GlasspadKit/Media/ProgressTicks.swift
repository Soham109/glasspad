import Foundation

/// When a playing song's progress bar and clock redraw. The bar redraws only once it has moved
/// a whole pixel, and the clock still turns over on each second: ticks are a whole fraction of
/// a second apart (1, 1/2, 1/3, 1/4 ...) and fall on the song's whole seconds.
public enum ProgressTicks {
    /// Seconds between redraws for a song of `duration` on a bar `barPixels` wide: the time the
    /// bar takes to move one pixel, but no more often than `fastest` and at least once a second.
    /// Before the bar has a width, `fastest`.
    public static func interval(duration: TimeInterval, barPixels: Double, fastest: TimeInterval) -> TimeInterval {
        let fastest = min(1, max(fastest, 1.0 / 60))
        guard duration > 0, barPixels >= 1 else { return fastest }
        let wanted = max(duration / barPixels, fastest)
        // A tiny allowance so 1 / 0.25 is 4 steps, not 3.
        let steps = max(1, Int((1 / wanted + 1e-9).rounded(.down)))
        return 1 / Double(steps)
    }

    /// How long after a whole second a tick lands, so the clock read at that moment is past
    /// the second, never a rounding error short of it.
    public static let lag: TimeInterval = 0.01

    /// The last tick at or before `now`, for `TimelineView(.periodic(from:by:))`, so the ticks
    /// that follow land just after the song's whole seconds.
    public static func start(now: Date, position: TimeInterval, interval: TimeInterval) -> Date {
        guard interval > 0, position.isFinite, position >= 0 else { return now }
        var back = (position - lag).truncatingRemainder(dividingBy: interval)
        if back < 0 { back += interval }
        return now.addingTimeInterval(-back)
    }
}
