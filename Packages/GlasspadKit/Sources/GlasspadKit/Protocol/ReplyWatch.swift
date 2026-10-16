import Foundation

/// One request that must be answered, like a Deck save. An older Mac drops a message it cannot
/// read without a word, so a request still unanswered at its deadline counts as failed rather
/// than done. A newer request replaces the one before it.
public struct ReplyWatch: Equatable, Sendable {
    public private(set) var generation = 0
    public private(set) var isWaiting = false

    public init() {}

    /// A request went out. Pass the result to `timedOut` at the deadline.
    public mutating func start() -> Int {
        generation += 1
        isWaiting = true
        return generation
    }

    /// The answer arrived (or the request was given up).
    public mutating func settle() { isWaiting = false }

    /// At the deadline of request `generation`: true, once, when it is the latest request and
    /// still has no answer.
    public mutating func timedOut(_ generation: Int) -> Bool {
        guard generation == self.generation, isWaiting else { return false }
        isWaiting = false
        return true
    }
}
