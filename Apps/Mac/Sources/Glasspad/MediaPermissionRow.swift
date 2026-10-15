import GlasspadMacCore
import SwiftUI

/// Shown in the menu when the user refused Automation for a music app, so Media mode on the
/// phone cannot read what it plays through Apple Events.
struct MediaPermissionRow: View {
    @ObservedObject private var permissions = MediaPermissions.shared

    var body: some View {
        if let app = permissions.deniedApps.first {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(app) Song Info")
                        .font(.headline)
                    Text("Allow Glasspad under Automation to show what \(app) plays on your iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Open…") { permissions.openAutomationSettings() }
                    .controlSize(.small)
                    .accessibilityHint("Opens Privacy and Security, Automation in System Settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}
