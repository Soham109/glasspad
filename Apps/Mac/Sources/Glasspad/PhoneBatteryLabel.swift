import GlasspadKit
import SwiftUI

/// The iPhone's battery at the end of its row, as macOS shows AirPods: "42%" and the battery.
struct PhoneBatteryLabel: View {
    let battery: PhoneBattery

    var body: some View {
        HStack(spacing: 4) {
            Text(battery.text)
                .font(.system(size: 11))
                .monospacedDigit()
            Image(systemName: battery.symbol)
                .font(.system(size: 13))
        }
        .foregroundStyle(.secondary)
        .accessibilityElement()
        .accessibilityLabel(Self.spoken(battery))
    }

    /// "Battery 42 percent, charging", for VoiceOver.
    static func spoken(_ battery: PhoneBattery) -> String {
        "Battery \(battery.percent) percent" + (battery.charging ? ", charging" : "")
    }
}
