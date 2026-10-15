import GlasspadKit
import GlasspadMacCore
import SwiftUI

/// Standard Settings window: one grouped Form per tab.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .frame(width: 480)
                .frame(minHeight: 420)
            TrackpadSettingsPane()
                .tabItem { Label("Trackpad", systemImage: "rectangle.and.hand.point.up.left") }
                .frame(width: 480)
                .frame(minHeight: 420)
            DeckSettings()
                .tabItem { Label("Deck", systemImage: "square.grid.3x2") }
                .frame(width: 480)
                .frame(minHeight: 420)
            MacrosSettings()
                .tabItem { Label("Macros", systemImage: "wand.and.stars") }
                .frame(width: 760, height: 560)
        }
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var controller: GlasspadController
    @StateObject private var login = LaunchAtLogin()

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                if login.needsApproval {
                    LabeledContent("Approval needed") {
                        Button("Open Login Items…") { SystemSettings.openLoginItems() }
                    }
                }
            }
            Section {
                MacDockSection()
                    .controlSize(.regular)
            } header: {
                Text("Mac Dock")
            } footer: {
                Text("Glasspad saves your Dock settings before hiding it and puts them back exactly when you turn this off, when the phone disconnects, and when Glasspad quits.")
                    .foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if controller.accessibilityTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") {
                            controller.requestAccessibility()
                            SystemSettings.openAccessibility()
                        }
                    }
                }
            }
            Section("Paired iPhones") {
                if controller.phones.isEmpty {
                    Text("No iPhones paired yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(controller.phones) { phone in
                    LabeledContent(phone.phoneName) {
                        Button("Revoke", role: .destructive) { controller.revoke(phone) }
                    }
                }
            }
            Section("Gestures") {
                ForEach(controller.capabilities.summary, id: \.gesture) { item in
                    LabeledContent(item.gesture.displayName, value: item.mode.label)
                        .help(item.mode.help)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
    }
}

/// Read-only mirror of the Mac's own trackpad settings, which Glasspad follows live.
private struct TrackpadSettingsPane: View {
    @EnvironmentObject private var controller: GlasspadController

    var body: some View {
        let s = controller.settings
        Form {
            Section {
                LabeledContent("Tracking speed", value: String(format: "%.2f", s.trackingSpeed))
                LabeledContent("Natural scrolling", value: s.naturalScrolling ? "On" : "Off")
                LabeledContent("Secondary click", value: s.secondaryClick.text)
                LabeledContent("Look up", value: s.lookUp.text)
                LabeledContent("Swipe between pages", value: s.swipeBetweenPages.text)
                LabeledContent("Swipe between spaces", value: s.swipeBetweenSpaces.text)
                LabeledContent("Mission Control", value: s.missionControl.text)
                LabeledContent("App Exposé", value: s.appExpose.text)
            } footer: {
                Text("Glasspad follows these settings from System Settings and updates when you change them. Tap to click is always on, because an iPhone screen cannot be pressed down.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Open Trackpad Settings…") { SystemSettings.openTrackpad() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DeckSettings: View {
    @EnvironmentObject private var controller: GlasspadController
    @State private var allowShell = DeckConfig.load().allowShellCommands

    var body: some View {
        Form {
            Section {
                Toggle("Allow shell command buttons", isOn: $allowShell)
                    .onChange(of: allowShell) { _, on in
                        var cfg = DeckConfig.load()
                        cfg.allowShellCommands = on
                        try? cfg.save()
                    }
            } footer: {
                Text("Shell commands run with your user account. Leave this off unless you wrote the commands yourself.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Show Deck File in Finder") {
                    let url = DeckConfig.defaultURL()
                    if !FileManager.default.fileExists(atPath: url.path) { try? DeckConfig.load().save() }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        .formStyle(.grouped)
    }
}

private extension SecondaryClick {
    var text: String {
        switch self {
        case .twoFinger: "Two fingers"
        case .bottomRight: "Bottom right corner"
        case .bottomLeft: "Bottom left corner"
        case .off: "Off"
        }
    }
}

private extension LookUp {
    var text: String {
        switch self {
        case .forceClick: "Force click"
        case .threeFingerTap: "Three finger tap"
        case .off: "Off"
        }
    }
}

private extension SwipePages {
    var text: String {
        switch self {
        case .twoFinger: "Two fingers"
        case .threeFinger: "Three fingers"
        case .twoOrThree: "Two or three fingers"
        case .off: "Off"
        }
    }
}

private extension FingerCount {
    var text: String {
        switch self {
        case .three: "Three fingers"
        case .four: "Four fingers"
        case .off: "Off"
        }
    }
}
