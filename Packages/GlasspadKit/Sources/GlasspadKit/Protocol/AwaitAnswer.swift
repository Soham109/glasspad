import Foundation

/// Waits for an answer that lands somewhere else, like a Mac's reply the session stores by
/// request id. Looks every `interval` until `answer` returns a value; nil when `timeout`
/// passes first (an older Mac drops a message it cannot read without a word) or the task
/// is cancelled. Runs on the caller's actor, so `answer` can read main actor state.
public func awaitAnswer<T>(timeout: Duration, every interval: Duration = .milliseconds(50),
                           isolation: isolated (any Actor)? = #isolation,
                           _ answer: () -> T?) async -> T? {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while true {
        if let value = answer() { return value }
        guard clock.now < deadline else { return nil }
        do { try await Task.sleep(for: interval) } catch { return answer() }
    }
}
