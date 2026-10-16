import Foundation

/// How many copies of one kind of view are on screen. A layout can show two at once (two
/// trackpad panes), and SwiftUI may run the new one's appear before the old one's disappear,
/// so a plain flag could end up off while one still shows.
public struct ShownCount: Equatable, Sendable {
    public private(set) var count = 0

    public init() {}

    public var isShown: Bool { count > 0 }

    /// One appeared (`true`) or disappeared (`false`). Never goes below zero.
    public mutating func set(_ shown: Bool) {
        count = max(0, count + (shown ? 1 : -1))
    }
}
