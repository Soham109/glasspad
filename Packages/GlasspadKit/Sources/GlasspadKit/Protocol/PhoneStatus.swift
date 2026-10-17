import Foundation

/// Phone -> Mac: how the iPhone itself is doing. Sent as `ControlMessage.phoneStatus` after
/// connecting and again when a field changes, so the Mac can show the iPhone's battery on its
/// row, as macOS does for AirPods.
///
/// Every field is optional and unknown fields are ignored, so either side can add fields
/// later. A Mac built before this message reads it as `.unknown` and drops it.
public struct PhoneStatus: Codable, Equatable, Sendable {
    /// Whole percent, 0...100. nil when iOS does not know (the simulator).
    public var batteryPercent: Int?
    /// Plugged in, charging or full.
    public var charging: Bool?

    public init(batteryPercent: Int? = nil, charging: Bool? = nil) {
        self.batteryPercent = batteryPercent
        self.charging = charging
    }

    /// From `UIDevice.batteryLevel` (0...1, or negative when unknown).
    public init(batteryLevel: Float, charging: Bool) {
        self.init(batteryPercent: batteryLevel < 0 ? nil : Int((min(1, batteryLevel) * 100).rounded()), charging: charging)
    }

    /// The battery to show, when the phone reported one.
    public var battery: PhoneBattery? {
        batteryPercent.map { PhoneBattery(percent: $0, charging: charging ?? false) }
    }

    private enum Keys: String, CodingKey { case batteryPercent, charging }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        // A value out of range or of another type reads as unknown rather than failing the message.
        batteryPercent = (try? c.decodeIfPresent(Int.self, forKey: .batteryPercent)).flatMap { $0 }
            .flatMap { (0...100).contains($0) ? $0 : nil }
        charging = (try? c.decodeIfPresent(Bool.self, forKey: .charging)).flatMap { $0 }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(batteryPercent, forKey: .batteryPercent)
        try c.encodeIfPresent(charging, forKey: .charging)
    }
}

/// The iPhone's battery as the Mac shows it: "42%" beside the battery symbol for that level.
public struct PhoneBattery: Equatable, Sendable {
    public var percent: Int
    public var charging: Bool

    public init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
    }

    public var text: String { "\(percent)%" }

    /// The SF Symbol nearest the level, with the bolt while charging, like the battery in the
    /// menu bar.
    public var symbol: String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
