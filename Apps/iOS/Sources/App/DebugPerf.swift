#if DEBUG
import GlasspadKit
import SwiftUI
import UIKit

/// Debug builds only (`-GPLaunchClock`): prints how long after the process started the first
/// frame was on screen, and when the main thread was next free (the first moment a touch
/// could be handled), so launch work can be measured from a script.
@MainActor
enum LaunchClock {
    private static var observer: NSObjectProtocol?

    static func start() {
        observer = NotificationCenter.default.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let observer = LaunchClock.observer else { return }
                NotificationCenter.default.removeObserver(observer)
                LaunchClock.observer = nil
                CATransaction.setCompletionBlock {
                    let frame = LaunchClock.sinceProcessStart
                    DispatchQueue.main.async {
                        DebugTour.say(String(format: "launch: first frame %.0f ms, main thread free %.0f ms",
                                             frame, LaunchClock.sinceProcessStart))
                    }
                }
            }
        }
    }

    /// Milliseconds since the kernel started this process (before dyld and every initializer).
    static var sinceProcessStart: Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
        let start = info.kp_proc.p_un.__p_starttime
        var now = timeval()
        gettimeofday(&now, nil)
        return Double(now.tv_sec - start.tv_sec) * 1000 + Double(now.tv_usec - start.tv_usec) / 1000
    }
}

/// Debug builds only (`-GPTour [rounds]`): visits every mode, tool, sheet, layout and a few
/// themes, then comes back to the trackpad, so memory after a tour can be compared with memory
/// after a fresh launch (scripts measure it with `footprint` and `leaks`). Prints "tour: done"
/// on standard output when it ends.
@MainActor
enum DebugTour {
    static func start(rounds: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            for round in 1...max(1, rounds) {
                await run()
                say("tour: round \(round) done")
            }
            say("tour: done")
        }
    }

    /// Standard output is buffered when it is not a terminal; flush so a script sees each line.
    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    private static func step(_ body: () -> Void) async {
        body()
        try? await Task.sleep(for: .seconds(1.2))
    }

    private static func run() async {
        let router = AppRouter.shared
        let settings = PhoneSettings.shared
        let start = settings.theme
        for mode in [AppMode.dock, .keys, .media, .actions, .deck, .macros, .clock, .nowPlaying, .calendar, .trackpad] {
            await step { router.show(mode) }
        }
        for tool in [AppMode.clipboard, .present, .remote, .displays] {
            await step { router.openTool(tool) }
            await step {
                router.showClipboard = false
                router.showPresenter = false
                router.showRemote = false
                router.showDisplays = false
            }
        }
        await step { router.showSettings = true }
        await step { router.showSettings = false }
        await step { router.showLayouts = true }
        await step { router.showLayouts = false }
        for id in ["studio", "trackpad-dock", "standby", "couch"] {
            guard let template = LayoutTemplate.builtIn.first(where: { $0.id == id }) else { continue }
            let store = LayoutStore.shared
            let layout = store.layouts.first { $0.name == template.name } ?? template.makeLayout()
            store.save(layout)
            await step { router.show(layout: layout) }
        }
        await step { router.show(.actions) }
        // Every theme in turn, as someone trying them in Settings > Theme would.
        for theme in ThemeChoice.allCases where theme != .photo {
            settings.theme = theme
            try? await Task.sleep(for: .seconds(0.4))
        }
        await step { settings.theme = start }
        await step { router.show(.trackpad) }
    }
}
#endif
