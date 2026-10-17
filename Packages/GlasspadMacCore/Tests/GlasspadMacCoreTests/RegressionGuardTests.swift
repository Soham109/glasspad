import CoreGraphics
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Bugs fixed on 16 October 2026, pinned so they cannot come back.
@Suite @MainActor struct RegressionGuardTests {
    // MARK: Mission Control, Show Desktop, App Exposé

    /// macOS 27 kills Mission Control's program when it is started directly. Whatever a Deck
    /// button does, with the Dock answering or not, that program is never run by path.
    @Test(arguments: [true, false])
    func noButtonEverRunsMissionControlsProgramDirectly(_ dockAnswers: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("guard-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try DeckConfig(allowShellCommands: false, buttons: [], pages: nil).save(to: url)
        let env = FakeDeckEnvironment()
        env.dockViewsWork = dockAnswers
        let d = DeckMode(env: env, url: url)
        for action in [DeckSystemAction.missionControl, .showDesktop, .appExpose] {
            _ = await d.perform(.system(action))
        }
        let direct = (env.runs + env.started).filter { $0.0.contains("Mission Control") || $0.0.contains("exposelauncher") }
        #expect(direct.isEmpty, "\(direct)")
        if dockAnswers {
            #expect(env.dockViews == [.missionControl, .showDesktop, .appExpose])
            #expect(env.runs.isEmpty && env.started.isEmpty && env.opened.isEmpty)
        } else {
            // Through Launch Services only: `open -b`, or opening the app by its bundle ID.
            #expect(env.runs.allSatisfy { $0.0 == "/usr/bin/open" && $0.1.contains("-b") })
            #expect(env.opened == [DeckMode.missionControlBundleID])
        }
    }

    /// Nothing in the Mac sources names Mission Control's executable inside its bundle.
    @Test func noSourceNamesMissionControlsExecutable() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        var checked = 0
        for folder in ["Packages/GlasspadMacCore/Sources", "Packages/GlasspadMacros/Sources", "Apps/Mac/Sources"] {
            let base = root.appendingPathComponent(folder)
            guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                checked += 1
                #expect(!text.contains("Mission Control.app/Contents/MacOS"), "\(file.lastPathComponent)")
            }
        }
        #expect(checked > 20)
    }

    // MARK: Split Screen across displays

    private func arranger(_ screens: [TilingScreen], waits: @escaping (TimeInterval) -> Void = { _ in }) -> WindowArranger {
        WindowArranger(displays: screens.map(\.frame), pause: waits)
    }

    /// The second window is on the laptop, the front one on the monitor, and the app lands
    /// moves a few reads late. It goes over first, is waited for until it is on the monitor,
    /// and only then gets its size, so the laptop never limits it.
    @Test(arguments: [SplitScreenTests.right, SplitScreenTests.left, SplitScreenTests.above])
    func aWindowFromAnotherDisplayArrivesBeforeItIsSizedEvenWhenItLandsLate(_ monitor: TilingScreen) async {
        let screens = [SplitScreenTests.laptop, monitor]
        let visibles = screens.map(\.visible)
        let front = FakeWindow("Safari", CGRect(x: monitor.visible.minX + 100, y: monitor.visible.minY + 100, width: 1200, height: 900),
                               displays: visibles)
        let behind = FakeWindow("Notes", CGRect(x: 100, y: 100, width: 1300, height: 800), displays: visibles)
        behind.lag = 3
        var waited: TimeInterval = 0
        let failure = await arranger(screens) { waited += $0 }
            .split(left: front, right: behind, in: monitor.visible, gap: 8, displayName: monitor.name)
        #expect(failure == nil)
        let halves = DisplayGeometry.split(in: monitor.visible, gap: 8)
        #expect(behind.actual == halves.right && front.actual == halves.left)
        let firstMove = behind.log.firstIndex { $0.hasPrefix("position") }
        let firstSize = behind.log.firstIndex { $0.hasPrefix("size") }
        #expect(firstMove != nil && firstSize != nil && firstMove! < firstSize!, "\(behind.log)")
        // It waited for the late landing, through the pause it was given.
        #expect(waited > 0)
    }

    // MARK: Full screen

    /// Every way of tiling takes a full-screen window out of full screen before it moves it.
    @Test(arguments: WindowArrangement.allCases)
    func fullScreenWindowsLeaveFullScreenBeforeTiling(_ arrangement: WindowArrangement) async {
        let screens = [SplitScreenTests.laptop]
        let count = arrangement.slots.count
        let windows = (0..<count).map { i in
            FakeWindow("App \(i)", CGRect(x: 100 + 40 * i, y: 100, width: 600, height: 500), displays: screens.map(\.visible))
        }
        windows.forEach { $0.fullScreen = true }
        let failure = await arranger(screens).arrange(windows, arrangement, in: SplitScreenTests.laptop.visible, gap: 8, displayName: "")
        #expect(failure == nil, "\(arrangement)")
        for w in windows {
            #expect(w.log.first == "exit full screen", "\(arrangement) \(w.appName): \(w.log)")
            #expect(!w.isFullScreen)
        }
    }

    @Test func oneWindowAndReturnToPreviousSizeLeaveFullScreenFirstToo() async {
        let screens = [SplitScreenTests.laptop]
        let w = FakeWindow("Terminal", CGRect(x: 0, y: 0, width: 1512, height: 982), displays: screens.map(\.visible), id: 9)
        w.fullScreen = true
        let a = arranger(screens)
        #expect(await a.leaveFullScreen(w))
        #expect(w.log == ["exit full screen"])
        // A window that will not leave is reported, never moved.
        let stuck = FakeWindow("Game", CGRect(x: 0, y: 0, width: 1512, height: 982), displays: screens.map(\.visible), id: 10)
        stuck.fullScreen = true
        stuck.staysFullScreen = true
        #expect(await a.leaveFullScreen(stuck) == false)
        #expect(!stuck.log.contains { $0.hasPrefix("position") || $0.hasPrefix("size") })
    }

    /// Leaving full screen waits up to two seconds for macOS's animation, through the async
    /// pause: the thread is never held while it waits.
    @Test func waitingForFullScreenToEndNeverHoldsTheThread() async {
        let screens = [SplitScreenTests.laptop]
        let w = FakeWindow("Terminal", CGRect(x: 0, y: 0, width: 1512, height: 982), displays: screens.map(\.visible))
        w.fullScreen = true
        var waited: TimeInterval = 0
        let start = Date()
        #expect(await arranger(screens) { waited += $0 }.leaveFullScreen(w))
        #expect(waited >= WindowArranger.afterFullScreen)
        #expect(Date().timeIntervalSince(start) < 0.25)
    }
}
