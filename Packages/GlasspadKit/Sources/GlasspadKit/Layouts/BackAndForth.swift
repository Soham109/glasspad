import Foundation

/// The screen before the one showing, for flipping back and forth between two of them (the
/// sideways swipe on the pill). Moving to the screen already showing changes nothing, so
/// flipping twice comes back to where it started.
public struct BackAndForth<Screen: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var previous: Screen?

    public init(previous: Screen? = nil) { self.previous = previous }

    public mutating func moved(from current: Screen, to next: Screen) {
        if current != next { previous = current }
    }
}
