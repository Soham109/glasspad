import AppKit
import GlasspadMacCore
import SwiftUI

@main
struct GlasspadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AppDelegate.controller

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(controller)
        } label: {
            MenuBarLabel(state: controller.linkState, macros: controller.macros)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let controller = GlasspadController()
    private let recordingIndicator = RecordingIndicator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, even when launched without the bundle's LSUIElement (swift run).
        NSApp.setActivationPolicy(.accessory)
        Self.controller.start()
        recordingIndicator.observe(Self.controller.macros)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.controller.stop()
    }
}
