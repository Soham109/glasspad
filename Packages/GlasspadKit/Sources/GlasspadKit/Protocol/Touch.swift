import Foundation
import CoreGraphics

/// Lifecycle phase of one finger, mirroring UITouch.Phase.
public enum TouchPhase: UInt8, Codable, Sendable {
    case began = 0, moved = 1, stationary = 2, ended = 3, cancelled = 4

    /// True while the finger is still on the surface.
    public var isActive: Bool { self == .began || self == .moved || self == .stationary }
}

/// One finger in a touch frame. `x` and `y` are in phone points, origin top left.
public struct Touch: Equatable, Sendable {
    public var id: UInt8
    public var phase: TouchPhase
    public var x: Double
    public var y: Double
    public var majorRadius: Double

    public init(id: UInt8, phase: TouchPhase, x: Double, y: Double, majorRadius: Double = 20) {
        self.id = id
        self.phase = phase
        self.x = x
        self.y = y
        self.majorRadius = majorRadius
    }
}

/// A full snapshot of every finger on the surface at one instant.
///
/// Contract: every frame lists every finger currently down. A finger that was in
/// the previous frame and is missing from this one is treated as lifted, so a lost
/// "ended" packet heals itself on the next frame.
public struct TouchFrame: Equatable, Sendable {
    public var seq: UInt32
    /// Phone monotonic clock, seconds.
    public var timestamp: TimeInterval
    public var touches: [Touch]
    /// Surface size in phone points.
    public var surface: CGSize

    public init(seq: UInt32, timestamp: TimeInterval, touches: [Touch], surface: CGSize) {
        self.seq = seq
        self.timestamp = timestamp
        self.touches = touches
        self.surface = surface
    }
}
