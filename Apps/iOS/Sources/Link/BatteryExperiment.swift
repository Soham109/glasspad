import GlasspadKit
import SwiftUI

/// Settings > Advanced, hidden unless asked for (`MacSession.showsBatteryExperiment`): when
/// the trackpad stops keeping Wi-Fi ready after the last touch. Two minutes is how Glasspad
/// ships; the Mac's log shows how late the first touch after a rest arrives with each choice.
struct BatteryExperimentSection: View {
    @Environment(\.palette) private var palette
    var session = MacSession.shared

    var body: some View {
        if session.showsBatteryExperiment {
            Section {
                Picker(selection: Binding(get: { session.heartbeatRest }, set: { session.heartbeatRest = $0 })) {
                    ForEach(HeartbeatRest.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Battery Experiment", systemImage: "battery.75percent")
                }
            } footer: {
                Text("How long the trackpad keeps Wi-Fi ready after your last touch. Shorter saves battery, but the first touch after a pause may arrive late. 2 Minutes is the normal setting.")
            }
            .listRowBackground(palette.raisedColor)
        }
    }
}
