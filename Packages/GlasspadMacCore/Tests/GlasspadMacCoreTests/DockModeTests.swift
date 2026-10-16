import AppKit
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

// isDirectory: true so the URL is the same whether or not Word is installed on the test machine.
private let wordURL = URL(fileURLWithPath: "/Applications/Microsoft Word.app", isDirectory: true)

nonisolated(unsafe) private let sample: [[String: Any]] = [
    ["tile-data": ["bundle-identifier": "com.microsoft.Word", "file-label": "Microsoft Word",
                   "file-data": ["_CFURLString": "file:///Applications/Microsoft%20Word.app/", "_CFURLStringType": 15]],
     "tile-type": "file-tile"],
    ["tile-data": ["file-label": "Spacer"], "tile-type": "spacer-tile"],
    ["tile-data": ["bundle-identifier": "com.apple.apps.launcher", "file-label": "Apps"], "tile-type": "file-tile"],
]

@Suite @MainActor struct DockModeTests {
    @Test func parsesPersistentApps() {
        let entries = DockMode.parsePersistentApps(sample)
        #expect(entries.map(\.bundleID) == ["com.microsoft.Word", "com.apple.apps.launcher"])
        #expect(entries[0].name == "Microsoft Word")
        #expect(entries[0].url?.path == "/Applications/Microsoft Word.app")
        #expect(DockMode.parsePersistentApps(nil).isEmpty)
    }

    @Test func mergeKeepsDockOrderThenRunningThenRecent() {
        let dock = DockMode.parsePersistentApps(sample)
        let running = [
            DockMode.RunningApp(bundleID: "com.apple.Terminal", name: "Terminal", url: nil, active: true),
            DockMode.RunningApp(bundleID: "com.microsoft.Word", name: "Word", url: nil, active: false, hidden: true),
        ]
        let recent = [DockMode.Entry(bundleID: "com.apple.Terminal", name: "Terminal", url: nil),
                      DockMode.Entry(bundleID: "com.apple.Notes", name: "Notes", url: nil)]
        let merged = DockMode.merge(dock: dock, running: running, recent: recent)
        #expect(merged.map(\.entry.bundleID) == ["com.microsoft.Word", "com.apple.apps.launcher", "com.apple.Terminal", "com.apple.Notes"])
        #expect(merged.map(\.running) == [true, false, true, false])
        #expect(merged.map(\.active) == [false, false, true, false])
        #expect(merged.map(\.inDock) == [true, true, false, false])
        #expect(merged.map(\.recent) == [false, false, false, true])
        #expect(merged[0].hidden)
    }

    @Test func recentListIsCapped() {
        let recent = (0..<20).map { DockMode.Entry(bundleID: "r\($0)", name: "R", url: nil) }
        #expect(DockMode.merge(dock: [], running: [], recent: recent).count == DockMode.recentLimit)
    }

    @Test func rendersSharpIconsAtThreeTimesTileSize() throws {
        #expect(DockApp.iconPixels >= 180)
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        let png = try #require(DockMode.renderPNG(image, pixels: DockApp.iconPixels))
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide == 384 && rep.pixelsHigh == 384)
    }

    @Test func realAppIconsHaveADetailedEnoughSourceForThePhone() throws {
        // macOS keeps app icons up to 1024 px, so 384 px is drawn down from a larger image,
        // never scaled up from a small one.
        let icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        #expect(icon.representations.map(\.pixelsWide).max() ?? 0 >= DockApp.iconPixels)
        let png = try #require(DockMode.renderPNG(icon, pixels: DockApp.iconPixels))
        #expect(NSBitmapImageRep(data: png)?.pixelsWide == DockApp.iconPixels)
        // A sane size for one icon over Wi-Fi.
        #expect(png.count < 400_000)
    }

    @Test func bigIconSetsAreSplitAcrossMessages() {
        let png = Data(count: 600_000)
        let apps = (0..<5).map { DockApp(bundleID: "a\($0)", name: "A", iconPNG: png, running: false, active: false) }
        let (list, later) = DockMode.splitIcons(apps, budget: 1_500_000)
        #expect(list.count == 5)
        #expect(list.filter { $0.iconPNG != nil }.count == 2)
        #expect(later.map(\.bundleID) == ["a2", "a3", "a4"])
        let batches = DockMode.iconBatches(later, budget: 1_500_000)
        #expect(batches.map { $0.map(\.bundleID) } == [["a2", "a3"], ["a4"]])
        // One icon bigger than the budget still goes, on its own.
        let huge = DockApp(bundleID: "h", name: "H", iconPNG: Data(count: 2_000_000), running: false, active: false)
        #expect(DockMode.splitIcons([huge]).later.isEmpty)
        #expect(DockMode.iconBatches([huge, huge]).count == 2)
    }

    @Test func iconsAreSentOncePerKeyAndKeyedByModificationDate() {
        let ws = FakeWorkspace()
        ws.persistent = sample
        ws.existing = [wordURL.path]
        ws.lsURLs = ["com.apple.apps.launcher": [URL(fileURLWithPath: "/System/Applications/Apps.app")]]
        ws.existing.insert("/System/Applications/Apps.app")
        let dock = DockMode(workspace: ws, cacheDirectory: nil)
        let first = dock.currentList()
        #expect(first.allSatisfy { $0.iconPNG != nil })
        #expect(first[0].iconKey == "com.microsoft.Word@1700000000-384")
        #expect(first[0].inDock == true)
        // Same session: no icons again.
        #expect(dock.currentList().allSatisfy { $0.iconPNG == nil })
        // New session, phone says it has Word's: only the other one comes.
        dock.resetSession()
        dock.phoneHas(iconKeys: ["com.microsoft.Word@1700000000-384"])
        let third = dock.currentList()
        #expect(third[0].iconPNG == nil && third[1].iconPNG != nil)
        // Rendered once per key; memory cache after that.
        #expect(ws.iconRenders == 2)
    }

    @Test func activationsFeedTheRecentList() {
        let ws = FakeWorkspace()
        let dock = DockMode(workspace: ws, cacheDirectory: nil)
        dock.noteActivated(.init(bundleID: "com.apple.Notes", name: "Notes", url: nil))
        dock.noteActivated(.init(bundleID: "com.apple.Maps", name: "Maps", url: nil))
        dock.noteActivated(.init(bundleID: "com.apple.Notes", name: "Notes", url: nil))
        #expect(dock.currentList().map(\.bundleID) == ["com.apple.Notes", "com.apple.Maps"])
        #expect(dock.currentList().allSatisfy { $0.recent == true })
    }

    @Test func appActionsUseTheRunningProcess() {
        let ws = FakeWorkspace()
        ws.running = [DockMode.RunningApp(bundleID: "com.microsoft.Word", name: "Word", url: wordURL, active: false, pid: 42)]
        let dock = DockMode(workspace: ws, cacheDirectory: nil)
        #expect(dock.perform(.hide, bundleID: "com.microsoft.Word"))
        #expect(dock.perform(.unhide, bundleID: "com.microsoft.Word"))
        #expect(dock.perform(.quit, bundleID: "com.microsoft.Word"))
        #expect(dock.perform(.revealInFinder, bundleID: "com.microsoft.Word"))
        #expect(ws.hidden == [42] && ws.unhidden == [42] && ws.terminated == [42])
        #expect(ws.revealed == [wordURL])
        #expect(!dock.perform(.quit, bundleID: "com.apple.Notes"))
    }

    @Test func catalogIsSortedAndUnique() {
        let ws = FakeWorkspace()
        ws.installed = [("b", "Zed", nil), ("a", "apple", nil), ("b", "Zed copy", nil)]
        let names = DockMode(workspace: ws, cacheDirectory: nil).catalog().map(\.name)
        #expect(names == ["apple", "Zed"])
    }
}

@Suite @MainActor struct AppLauncherTests {
    private func run(_ ws: FakeWorkspace, _ id: String, preferred: URL? = nil) -> AppLauncher.Outcome? {
        var out: AppLauncher.Outcome?
        AppLauncher(workspace: ws).open(bundleID: id, preferredURL: preferred) { out = $0 }
        return out
    }

    /// The Word report: Word is running with no window on screen. Activation alone did nothing,
    /// so the launcher also sends the Dock's reopen event and, when still behind, forces it front.
    @Test func runningWordIsActivatedReopenedAndForcedFront() {
        let ws = FakeWorkspace()
        ws.running = [DockMode.RunningApp(bundleID: "com.microsoft.Word", name: "Microsoft Word", url: wordURL,
                                          active: false, hidden: true, pid: 73247)]
        ws.front = "com.apple.Safari"
        ws.frontAfterActivate = nil   // cooperative activation ignored the request
        let outcome = run(ws, "com.microsoft.Word")
        #expect(outcome == .activated(wordURL))
        #expect(ws.unhidden == [73247])
        #expect(ws.activated == [73247])
        #expect(ws.launches.map(\.path) == [wordURL.path])
        #expect(ws.launches.map(\.reopen) == [true])
        #expect(ws.forcedFront == [73247])
    }

    @Test func runningAppThatComesFrontIsNotForced() {
        let ws = FakeWorkspace()
        ws.running = [DockMode.RunningApp(bundleID: "com.apple.Notes", name: "Notes", url: nil, active: false, pid: 9)]
        ws.frontAfterActivate = "com.apple.Notes"
        #expect(run(ws, "com.apple.Notes") == .activated(nil))
        #expect(ws.forcedFront.isEmpty)
        #expect(ws.unhidden.isEmpty)
    }

    @Test func notRunningLaunchesFromTheDockURLFirst() {
        let ws = FakeWorkspace()
        ws.existing = [wordURL.path]
        ws.bundleIDs = [wordURL.path: "com.microsoft.Word"]
        ws.lsURLs = ["com.microsoft.Word": [wordURL]]
        #expect(run(ws, "com.microsoft.Word", preferred: URL(string: "file:///Applications/Microsoft%20Word.app/")) == .launched(wordURL))
        #expect(ws.launches.map(\.path) == [wordURL.path])
        #expect(ws.launches.map(\.reopen) == [false])
    }

    @Test func appOutsideApplicationsIsFoundAndStaleDockURLSkipped() {
        let ws = FakeWorkspace()
        let stale = URL(fileURLWithPath: "/Applications/Old Word.app", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/me/Applications/Microsoft Word.app")
        ws.existing = [stale.path, home.path]
        ws.bundleIDs = [stale.path: "com.microsoft.Word.old", home.path: "com.microsoft.Word"]
        ws.installed = [("com.microsoft.Word", "Microsoft Word", home)]
        #expect(run(ws, "com.microsoft.Word", preferred: stale) == .launched(home))
        #expect(ws.launches.map(\.path) == [home.path])
    }

    @Test func failedLaunchFallsBackToTheNextCopyThenReportsWhy() {
        let ws = FakeWorkspace()
        let a = URL(fileURLWithPath: "/Applications/Microsoft Word.app", isDirectory: true)
        let b = URL(fileURLWithPath: "/Volumes/Apps/Microsoft Word.app")
        ws.existing = [a.path, b.path]
        ws.lsURLs = ["com.microsoft.Word": [a, b]]
        ws.launchErrors = [a.path: "damaged"]
        #expect(run(ws, "com.microsoft.Word") == .launched(b))
        ws.launches = []
        ws.launchErrors = [a.path: "damaged", b.path: "needs update"]
        #expect(run(ws, "com.microsoft.Word") == .failed("needs update"))
        #expect(ws.launches.count == 2)
    }

    @Test func missingAppSaysSo() {
        let outcome = run(FakeWorkspace(), "com.example.nothing")
        #expect(outcome?.ok == false)
        #expect(outcome?.message == "This app is not installed on your Mac.")
    }
}

@Suite @MainActor struct MacDockHiderTests {
    @Test func hideSavesExactValuesAndRestoreWritesThemBack() {
        let dock = FakeDefaults()
        dock.values["com.apple.dock"] = ["autohide": false, "autohide-delay": 0.2, "tilesize": 48]
        let (hider, _, own, runner) = FakeDockHider.make(dock: dock)
        hider.setManual(true)
        let d = dock.values["com.apple.dock"]!
        #expect(d["autohide"] as? Bool == true)
        #expect(d["autohide-delay"] as? Double == MacDockHider.hiddenDelay)
        #expect(d["autohide-time-modifier"] as? Double == 0)
        #expect(hider.isHidden)
        #expect(own.dictionary(forKey: MacDockHider.savedKey) != nil)
        #expect(runner.calls.map(\.0) == ["/usr/bin/killall"])

        hider.setManual(false)
        let r = dock.values["com.apple.dock"]!
        #expect(r["autohide"] as? Bool == false)
        #expect(r["autohide-delay"] as? Double == 0.2)
        #expect(r["autohide-time-modifier"] == nil)   // was not set before: deleted again
        #expect(r["tilesize"] as? Int == 48)          // untouched
        #expect(!hider.isHidden)
        #expect(own.dictionary(forKey: MacDockHider.savedKey) == nil)
        #expect(runner.calls.count == 2)
    }

    @Test func hidingTwiceKeepsTheOriginalValues() {
        let dock = FakeDefaults()
        dock.values["com.apple.dock"] = ["autohide": false]
        let (hider, _, _, runner) = FakeDockHider.make(dock: dock)
        hider.setManual(true)
        hider.setHideWhileConnected(true)
        hider.setConnected(true)
        #expect(runner.calls.count == 1)
        hider.setManual(false)            // still connected with the option on: stays hidden
        #expect(hider.isHidden)
        hider.setConnected(false)
        #expect(dock.values["com.apple.dock"]?["autohide"] as? Bool == false)
        #expect(runner.calls.count == 2)
    }

    @Test func whileConnectedFollowsTheSession() {
        let (hider, dock, _, _) = FakeDockHider.make()
        hider.setConnected(true)
        #expect(!hider.isHidden)          // option off
        hider.setHideWhileConnected(true)
        #expect(hider.isHidden)
        hider.setConnected(false)
        #expect(!hider.isHidden)
        #expect(dock.values["com.apple.dock"]?["autohide"] == nil)
    }

    @Test func crashIsUndoneOnNextLaunch() {
        let suite = "glasspad-tests-\(UUID().uuidString)"
        let dock = FakeDefaults()
        dock.values["com.apple.dock"] = ["autohide": true, "autohide-delay": 0.5, "autohide-time-modifier": 0.7]
        do {
            let (hider, _, _, _) = FakeDockHider.make(dock: dock, suite: suite)
            hider.setManual(true)
            // The app dies here: no restore.
        }
        #expect(dock.values["com.apple.dock"]?["autohide-delay"] as? Double == MacDockHider.hiddenDelay)
        let (next, _, _, runner) = FakeDockHider.make(dock: dock, suite: suite)
        #expect(next.isHidden)
        next.recoverAfterCrash()
        #expect(!next.isHidden)
        #expect(!next.manual)
        let d = dock.values["com.apple.dock"]!
        #expect(d["autohide"] as? Bool == true)
        #expect(d["autohide-delay"] as? Double == 0.5)
        #expect(d["autohide-time-modifier"] as? Double == 0.7)
        #expect(runner.calls.count == 1)
        next.recoverAfterCrash()          // nothing saved now: nothing written
        #expect(runner.calls.count == 1)
    }

    @Test func quitRestoresAndOptionIsRemembered() {
        let suite = "glasspad-tests-\(UUID().uuidString)"
        let (hider, dock, _, _) = FakeDockHider.make(suite: suite)
        hider.set(MacDockState(hidden: false, hideWhileConnected: true))
        hider.setConnected(true)
        #expect(hider.isHidden)
        hider.appWillTerminate()
        #expect(!hider.isHidden)
        #expect(dock.values["com.apple.dock"]?["autohide"] == nil)
        let (again, _, _, _) = FakeDockHider.make(suite: suite)
        #expect(again.hideWhileConnected)
        #expect(!again.manual)
    }

    /// Reliability M3: the record of what to restore must be on disk before the Dock is changed,
    /// or a power loss right after leaves the Dock hidden with nothing to restore it from.
    @Test func savedValuesAreFlushedBeforeTheDockIsTouched() throws {
        let (hider, dock, own, _) = FakeDockHider.make()
        hider.setManual(true)
        let firstDockWrite = try #require(dock.log.firstIndex { $0.hasPrefix("set ") })
        let flush = try #require(dock.log.firstIndex(of: "flush own"))
        #expect(flush < firstDockWrite)
        #expect(own.dictionary(forKey: MacDockHider.savedKey) != nil)
        dock.log = []
        hider.setManual(false)
        #expect(dock.log.last == "flush own")      // the cleared record is flushed too
    }

    @Test func phoneIsToldAboutChanges() {
        let (hider, _, _, _) = FakeDockHider.make()
        var seen: [MacDockState] = []
        hider.onChange = { seen.append($0) }
        hider.setManual(true)
        hider.setManual(false)
        #expect(seen.map(\.isHiddenNow) == [true, false])
        #expect(seen.first?.hidden == true)
    }
}
