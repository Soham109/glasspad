import AppKit
import GlasspadKit
import GlasspadMacCore
import SwiftUI

@main
struct GlasspadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Not observed here: the scenes never change, so a model change must not rebuild them
    /// (that redrew the menu bar icon on every status tick). Each view observes what it shows.
    private let model = AppDelegate.model

    var body: some Scene {
        // The live check runs on its own, with no menu bar item and no phone listening.
        MenuBarExtra(isInserted: .constant(!LiveCheckWindow.requested)) {
            PopoverView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(status: AppDelegate.menuBarStatus)
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
    static let menuBarStatus = MenuBarStatus(model: model)
    private let recordingIndicator = RecordingIndicator()
    private let welcome = WelcomeWindow()
    private let liveCheck = LiveCheckWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, even when launched without the bundle's LSUIElement (swift run).
        NSApp.setActivationPolicy(.accessory)
        if LiveCheckWindow.requested {
            liveCheck.show(router: Self.controller.modeRouter)
            return
        }
        ActivityLog.shared.start()
        ActivityLog.shared.record("app", ["side": "mac", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                                          "os": ProcessInfo.processInfo.operatingSystemVersionString])
        Self.controller.start()
        recordingIndicator.observe(Self.controller.macros)
        // First launch (or every phone forgotten): open a window with the code and the steps
        // instead of sitting silently in the menu bar.
        if Self.model.phones.isEmpty { welcome.show(Self.model) }
    }

    /// With the Mac's Dock hidden, quitting waits (without holding the main thread) until the
    /// Dock is back, then finishes. Two seconds at most, so a stuck restart never blocks quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard MacDockHider.shared.isHidden else { return .terminateNow }
        var answered = false
        let finish = {
            guard !answered else { return }
            answered = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        MacDockHider.shared.restoreBeforeQuit { finish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { finish() }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Put the Mac's own Dock back before anything else.
        MacDockHider.shared.appWillTerminate()
        if !Self.model.isPaused, !LiveCheckWindow.requested { Self.controller.stop() }
    }
}
