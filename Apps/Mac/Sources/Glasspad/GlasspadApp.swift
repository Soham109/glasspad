import AppKit
import GlasspadMacCore
import SwiftUI

@main
struct GlasspadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppDelegate.model

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let controller = GlasspadController()
    static let model = AppModel.live(controller)
    private let recordingIndicator = RecordingIndicator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, even when launched without the bundle's LSUIElement (swift run).
        NSApp.setActivationPolicy(.accessory)
        Self.controller.start()
        recordingIndicator.observe(Self.controller.macros)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Put the Mac's own Dock back before anything else.
        MacDockHider.shared.appWillTerminate()
        if !Self.model.isPaused { Self.controller.stop() }
    }
}
