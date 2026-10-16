import CoreGraphics
import Foundation
import Testing
@testable import GlasspadKit
@testable import GlasspadMacCore

/// A Mac with a laptop and a display to its right; records what it was asked to do.
@MainActor
final class FakeDisplays: DisplaysBackend {
    var shown: [MacDisplay] = [
        MacDisplay(id: 1, name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                   visibleFrame: CGRect(x: 0, y: 37, width: 1512, height: 875), isMain: true, isBuiltIn: true,
                   notchWidth: 186, brightness: 0.5,
                   resolutions: [DisplayResolution(id: 10, width: 1312, height: 848),
                                 DisplayResolution(id: 11, width: 1512, height: 982, isDefault: true)], resolutionID: 11),
        MacDisplay(id: 2, name: "Studio Display", frame: CGRect(x: 1512, y: -458, width: 2560, height: 1440),
                   visibleFrame: CGRect(x: 1512, y: -458, width: 2560, height: 1440), isMain: false),
    ]
    var open: [MacWindow] = [
        MacWindow(id: 100, bundleID: "com.apple.Safari", appName: "Safari", title: "Apple", frame: CGRect(x: 100, y: 100, width: 800, height: 600)),
        MacWindow(id: 101, bundleID: "com.apple.mail", appName: "Mail", frame: CGRect(x: 1700, y: -300, width: 1000, height: 800)),
    ]
    var trusted = true
    var operations: [(UInt32, WindowOperation)] = []
    var applied: [(DisplayChange, Bool)] = []
    var restored = 0
    var brightness: [(UInt32, Double)] = []
    var failing: String?

    func displays() -> [MacDisplay] { shown }
    /// How often the full window list was read (on the Mac it asks every app through Accessibility).
    var windowListReads = 0
    func windows() -> [MacWindow] {
        windowListReads += 1
        return open
    }
    func frame(of window: UInt32) -> CGRect? { open.first { $0.id == window }?.frame }
    var canArrangeWindows: Bool { trusted }
    var tileMargin: CGFloat { 0 }

    func perform(_ operation: WindowOperation, window: UInt32) async -> String? {
        operations.append((window, operation))
        if let failing { return failing }
        func frame(_ id: UInt32, _ f: CGRect) { if let i = open.firstIndex(where: { $0.id == id }) { open[i].frame = f } }
        switch operation {
        case .setFrame(let f): frame(window, f)
        case .split(let other, let visible, let gap, _):
            let halves = DisplayGeometry.split(in: visible, gap: gap)
            frame(window, halves.left)
            frame(other, halves.right)
        case .arrange(let arrangement, let others, let visible, let gap, _):
            for (id, slot) in zip([window] + others, arrangement.slots) { frame(id, DisplayGeometry.frame(of: slot, in: visible, gap: gap)) }
        default: break
        }
        return nil
    }

    func apply(_ change: DisplayChange, permanently: Bool) -> Bool {
        applied.append((change, permanently))
        return true
    }

    func restorePermanent() { restored += 1 }
    func setBrightness(_ value: Double, display: UInt32) { brightness.append((display, value)) }
    var highlighted: [CGRect] = []
    func highlight(_ frame: CGRect) { highlighted.append(frame) }
}

@Suite @MainActor struct DisplaysModeTests {
    private func mode() -> (DisplaysMode, FakeDisplays, () -> [ModeMessage]) {
        let fake = FakeDisplays()
        let m = DisplaysMode(backend: fake)
        var sent: [ModeMessage] = []
        m.send = { sent.append($0) }
        return (m, fake, { sent })
    }

    private func result(_ sent: [ModeMessage], _ id: UUID) -> (ok: Bool, message: String?)? {
        for case .displaysResult(let i, let ok, let message) in sent where i == id { return (ok, message) }
        return nil
    }

    @Test func aHighlightOutlinesTheWindowWithoutAnswerOrMoving() {
        let (m, fake, sent) = mode()
        #expect(m.state().highlightsWindows == true)
        fake.windowListReads = 0
        m.highlight(windowID: 101)
        #expect(fake.highlighted == [CGRect(x: 1700, y: -300, width: 1000, height: 800)])
        // A window that has closed: nothing. Never an answer, never a move.
        m.highlight(windowID: 999)
        #expect(fake.highlighted.count == 1)
        #expect(sent().isEmpty && fake.operations.isEmpty)
        // One window's frame only, never the full list.
        #expect(fake.windowListReads == 0)
    }

    @Test func theOutlineLandsOnTheWindowInAppKitCoordinates() {
        // Quartz: top-left origin on the main display, y down. AppKit: bottom-left, y up.
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(WindowHighlight.appKitFrame(CGRect(x: 100, y: 100, width: 800, height: 600), mainHeight: main.height)
                == CGRect(x: 100, y: 282, width: 800, height: 600))
        // A display above the main one has negative Quartz y and lands above it in AppKit.
        #expect(WindowHighlight.appKitFrame(CGRect(x: 1700, y: -300, width: 1000, height: 200), mainHeight: main.height)
                == CGRect(x: 1700, y: 1082, width: 1000, height: 200))
    }

    @Test func watchingSendsOnlyChangesWithIconsFirstAndStopsWhenAsked() {
        let (m, fake, sent) = mode()
        var asked: [[String]] = []
        m.icons = { ids in
            asked.append(ids)
            return ids.map { DockApp(bundleID: $0, name: $0, iconPNG: Data([1]), running: true, active: false) }
        }
        m.watch(true)
        #expect(sent().count == 2)
        guard case .dockIcons(let apps) = sent()[0], case .displaysState(let s) = sent()[1] else { Issue.record("wrong order"); return }
        #expect(apps.map(\.bundleID) == ["com.apple.Safari", "com.apple.mail"])
        #expect(s.windows.count == 2 && s.displays.count == 2 && s.canArrangeWindows)
        // Nothing changed: nothing sent.
        m.push()
        #expect(sent().count == 2)
        // A window moved: a new state, and no icons again for apps already sent.
        fake.open[0].frame.origin.x = 300
        fake.open.append(MacWindow(id: 102, bundleID: "com.apple.mail", appName: "Mail", frame: CGRect(x: 0, y: 40, width: 500, height: 400)))
        m.push()
        #expect(sent().count == 3 && asked.count == 1)
        m.watch(false)
        fake.open[0].frame.origin.x = 400
        m.push()
        #expect(sent().count == 3)
        // A new session sends icons again.
        m.sessionEnded()
        m.watch(true)
        #expect(asked.count == 2)
        m.watch(false)
    }

    @Test func tilesAndMovesUseTheDisplayTheWindowIsOn() async {
        let (m, fake, sent) = mode()
        let id = UUID()
        await m.handle(id: id, windowID: 101, command: .tile(.leftHalf)).value
        #expect(result(sent(), id)?.ok == true)
        // Mail is on the Studio Display: its left half.
        #expect(fake.operations.first?.1 == .setFrame(CGRect(x: 1512, y: -458, width: 1280, height: 1440)))
        #expect(fake.operations.last?.1 == .raise)
        // To the laptop, keeping its place: a left half stays a left half.
        await m.handle(id: UUID(), windowID: 101, command: .move(display: 1, origin: nil)).value
        #expect(fake.open[1].frame == CGRect(x: 0, y: 37, width: 756, height: 875))
        // Dropped at a point on the same display: goes there, kept inside.
        await m.handle(id: UUID(), windowID: 100, command: .move(display: 1, origin: CGPoint(x: 1400, y: 500))).value
        #expect(fake.open[0].frame == CGRect(x: 712, y: 312, width: 800, height: 600))
    }

    @Test func splitPutsBothWindowsSideBySideAndRaisesBoth() async {
        let (m, fake, sent) = mode()
        let id = UUID()
        await m.handle(id: id, windowID: 100, command: .split(with: 101)).value
        #expect(result(sent(), id)?.ok == true)
        #expect(fake.open[0].frame == CGRect(x: 0, y: 37, width: 756, height: 875))
        #expect(fake.open[1].frame == CGRect(x: 756, y: 37, width: 756, height: 875))
        // One step for both (on Safari's display, the laptop), then Mail and Safari forward.
        #expect(fake.operations.first?.1 == .split(with: 101, visible: CGRect(x: 0, y: 37, width: 1512, height: 875), gap: 0,
                                                   display: "Built-in Retina Display"))
        #expect(fake.operations.suffix(2).map(\.0) == [101, 100])
        // With itself: refused.
        let again = UUID()
        await m.handle(id: again, windowID: 100, command: .split(with: 100)).value
        #expect(result(sent(), again)?.ok == false)
    }

    @Test func refusalsSayWhy() async {
        let (m, fake, sent) = mode()
        let gone = UUID()
        await m.handle(id: gone, windowID: 999, command: .raise).value
        #expect(result(sent(), gone)?.message == "That window has closed.")
        fake.trusted = false
        let blocked = UUID()
        await m.handle(id: blocked, windowID: 100, command: .tile(.fill)).value
        #expect(result(sent(), blocked)?.message?.contains("Accessibility") == true)
        #expect(fake.operations.isEmpty)
        // Raising needs no permission.
        let raise = UUID()
        await m.handle(id: raise, windowID: 100, command: .raise).value
        #expect(result(sent(), raise)?.ok == true)
        fake.trusted = true
        fake.failing = "That window cannot be moved."
        let refused = UUID()
        await m.handle(id: refused, windowID: 100, command: .close).value
        #expect(result(sent(), refused)?.message == "That window cannot be moved.")
        let noDisplay = UUID()
        await m.handle(id: noDisplay, windowID: 100, command: .move(display: 7, origin: nil)).value
        #expect(result(sent(), noDisplay)?.ok == false)
    }

    @Test func riskyChangesWaitForKeepAndGoBackByThemselves() throws {
        let (m, fake, sent) = mode()
        var clock = Date(timeIntervalSince1970: 1000)
        m.now = { clock }
        m.watch(true)
        let id = UUID()
        m.handle(id: id, command: .resolution(display: 1, id: 10))
        #expect(result(sent(), id)?.ok == true)
        #expect(fake.applied.last?.0 == .resolution(display: 1, id: 10) && fake.applied.last?.1 == false)
        #expect(m.state().pending == PendingDisplayChange(summary: "Built-in Retina Display looks like 1312 × 848.", secondsLeft: 15))
        clock += 4.2
        #expect(m.state().pending?.secondsLeft == 11)
        // Anything else waits until then.
        let other = UUID()
        m.handle(id: other, command: .makeMain(display: 2))
        #expect(result(sent(), other)?.message == "Keep or revert the last change first.")
        // Keep: made permanent.
        m.handle(id: UUID(), command: .keepChanges)
        #expect(fake.applied.last?.0 == .resolution(display: 1, id: 10) && fake.applied.last?.1 == true)
        #expect(m.state().pending == nil)

        // Mirroring, then Revert.
        m.handle(id: UUID(), command: .mirror(display: 2, of: 1))
        #expect(m.state().pending?.summary == "Studio Display shows the same picture as Built-in Retina Display.")
        m.handle(id: UUID(), command: .revertChanges)
        #expect(fake.restored == 1 && m.state().pending == nil)

        // No answer: back by itself when time runs out, and the phone hears about it.
        m.handle(id: UUID(), command: .mirror(display: 2, of: 1))
        let before = sent().count
        m.timedOut(UUID())                      // a stale timer changes nothing
        #expect(fake.restored == 1)
        m.timedOut(try #require(m.pendingToken))
        #expect(fake.restored == 2 && m.state().pending == nil && sent().count > before)
        m.watch(false)
    }

    @Test func safeChangesApplyAtOnce() {
        let (m, fake, sent) = mode()
        m.handle(id: UUID(), command: .brightness(display: 1, value: 1.4))
        #expect(fake.brightness.last! == (1, 1))
        let external = UUID()
        m.handle(id: external, command: .brightness(display: 2, value: 0.3))
        #expect(result(sent(), external)?.ok == false)
        m.handle(id: UUID(), command: .makeMain(display: 2))
        #expect(fake.applied.last?.0 == .origins([DisplayOrigin(display: 1, origin: CGPoint(x: -1512, y: 458)),
                                                 DisplayOrigin(display: 2, origin: .zero)]))
        #expect(fake.applied.last?.1 == true)
        // An arrangement is moved so the main display stays at 0, 0.
        m.handle(id: UUID(), command: .arrange([DisplayOrigin(display: 1, origin: CGPoint(x: 10, y: 10)),
                                                DisplayOrigin(display: 2, origin: CGPoint(x: -2550, y: 10))]))
        #expect(fake.applied.last?.0 == .origins([DisplayOrigin(display: 1, origin: .zero),
                                                 DisplayOrigin(display: 2, origin: CGPoint(x: -2560, y: 0))]))
        let unknown = UUID()
        m.handle(id: unknown, command: .resolution(display: 1, id: 77))
        #expect(result(sent(), unknown)?.message == "That resolution is not available.")
        // Already in use, or turning off a mirror that is off: nothing to do, nothing waits.
        m.handle(id: UUID(), command: .resolution(display: 1, id: 11))
        m.handle(id: UUID(), command: .mirror(display: 2, of: nil))
        #expect(m.state().pending == nil)
    }

    @Test func arrangementsThatStrandADisplayAreRefused() {
        let (m, fake, sent) = mode()
        func refused(_ origins: [DisplayOrigin]) -> Bool {
            let id = UUID()
            let before = fake.applied.count
            m.handle(id: id, command: .arrange(origins))
            return result(sent(), id)?.ok == false && fake.applied.count == before
        }
        // Far away, overlapping, touching only at a corner, or too large for CoreGraphics.
        #expect(refused([DisplayOrigin(display: 2, origin: CGPoint(x: 5000, y: 0))]))
        #expect(refused([DisplayOrigin(display: 2, origin: CGPoint(x: 100, y: 100))]))
        #expect(refused([DisplayOrigin(display: 2, origin: CGPoint(x: 1512, y: 982))]))
        #expect(refused([DisplayOrigin(display: 2, origin: CGPoint(x: 1e20, y: 0))]))
        #expect(refused([DisplayOrigin(display: 1, origin: CGPoint(x: -1e20, y: 0)), DisplayOrigin(display: 2, origin: .zero)]))
        // The same display twice, or one that copies another.
        #expect(refused([DisplayOrigin(display: 2, origin: CGPoint(x: 1512, y: 0)), DisplayOrigin(display: 2, origin: CGPoint(x: 5000, y: 0))]))
        fake.shown[1].mirrorOf = 1
        #expect(refused([DisplayOrigin(display: 2, origin: CGPoint(x: -2560, y: 0))]))
        fake.shown[1].mirrorOf = nil
        // Below the laptop, sharing part of its bottom edge: fine.
        #expect(!refused([DisplayOrigin(display: 2, origin: CGPoint(x: -500, y: 982))]))
        #expect(fake.applied.last?.0 == .origins([DisplayOrigin(display: 2, origin: CGPoint(x: -500, y: 982))]))
    }

    @Test func mirroringAMirrorIsRefused() {
        let (m, fake, sent) = mode()
        fake.shown.append(MacDisplay(id: 3, name: "Projector", frame: CGRect(x: 1512, y: -458, width: 2560, height: 1440),
                                     visibleFrame: CGRect(x: 1512, y: -458, width: 2560, height: 1440), isMain: false, mirrorOf: 2))
        // 2 copying 3, which already copies 2, would be a loop.
        let loop = UUID()
        m.handle(id: loop, command: .mirror(display: 2, of: 3))
        #expect(result(sent(), loop)?.ok == false)
        let chain = UUID()
        m.handle(id: chain, command: .mirror(display: 1, of: 3))
        #expect(result(sent(), chain)?.ok == false)
        #expect(fake.applied.isEmpty && m.state().pending == nil)
    }

    @Test func aMoveToAPointFarAwayStaysOnTheDisplay() async {
        let (m, fake, _) = mode()
        await m.handle(id: UUID(), windowID: 100, command: .move(display: 1, origin: CGPoint(x: 1e300, y: -1e300))).value
        #expect(fake.open[0].frame == CGRect(x: 712, y: 37, width: 800, height: 600))
    }

    @Test func arrangementsGoToTheMacAsOneStepAndSplitViewStartsOnItsDisplay() async {
        let (m, fake, sent) = mode()
        fake.open.append(MacWindow(id: 102, bundleID: "com.apple.Notes", appName: "Notes", frame: CGRect(x: 200, y: 200, width: 500, height: 400)))
        // The Mac says what it takes.
        #expect(m.state().offeredArrangements == WindowArrangement.allCases)
        let id = UUID()
        await m.handle(id: id, windowID: 101, command: .arrange(.quarters, windows: [101, 100, 102], display: 1)).value
        let laptop = fake.shown[0]
        guard case .arrange(.quarters, let others, let visible, _, let name)? = fake.operations.last?.1 else {
            Issue.record("not arranged")
            return
        }
        #expect(fake.operations.last?.0 == 101 && others == [100, 102] && visible == laptop.visibleFrame && name == laptop.name)
        #expect(fake.open.first { $0.id == 101 }?.frame == DisplayGeometry.frame(of: .topLeft, in: laptop.visibleFrame))
        #expect(sent().contains(.displaysResult(id: id, ok: true, message: nil)))
        // Split View on the Studio Display for a laptop window: over there first, then Split View.
        fake.operations = []
        await m.handle(id: UUID(), windowID: 100, command: .arrange(.fullScreen, windows: [100, 101], display: 2)).value
        #expect(fake.operations.count == 2 && fake.operations.last.map { $0.0 == 100 && $0.1 == .fullScreenSplit(with: 101) } == true)
        if case .setFrame(let f)? = fake.operations.first?.1 { #expect(fake.shown[1].frame.contains(f)) } else { Issue.record("not moved over") }
        // Gone, twice or too few: nothing is moved.
        fake.operations = []
        await m.handle(id: UUID(), windowID: 100, command: .arrange(.leftAndRight, windows: [100, 100], display: 1)).value
        await m.handle(id: UUID(), windowID: 100, command: .arrange(.quarters, windows: [100, 101], display: 1)).value
        await m.handle(id: UUID(), windowID: 100, command: .arrange(.leftAndRight, windows: [101, 100], display: 1)).value
        #expect(fake.operations.isEmpty)
    }

    @Test func theRouterPassesDisplaysMessagesAndStopsOnDisconnect() async {
        let poster = CapturingEventPoster()
        let keys = KeysMode(poster: poster, source: nil)
        let r = ModeRouter(keys: keys, dock: DockMode(workspace: FakeWorkspace(), cacheDirectory: nil), media: MediaMode(poster: poster),
                           deck: DeckMode(env: FakeDeckEnvironment(), url: tempURL("deck.json")), clipboard: ClipboardMode(),
                           present: PresentMode(keys: keys), macDock: FakeDockHider.make().hider)
        r.disconnectGrace = 0
        var sent: [ModeMessage] = []
        r.send = { sent.append($0) }
        let fake = FakeDisplays()
        r.displays = DisplaysMode(backend: fake)
        r.handle(.displaysWatch(on: true))
        #expect(sent.contains { if case .displaysState = $0 { true } else { false } })
        let id = UUID()
        r.handle(.windowCommand(id: id, windowID: 100, command: .minimize))
        // Window commands run as a task, so the main thread is free while windows land.
        for _ in 0..<100 where !sent.contains(.displaysResult(id: id, ok: true, message: nil)) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(fake.operations.last?.1 == .minimize && sent.contains(.displaysResult(id: id, ok: true, message: nil)))
        r.handle(.displayCommand(id: id, command: .brightness(display: 1, value: 0.2)))
        #expect(fake.brightness.last! == (1, 0.2))
        r.sessionEnded()
        #expect(r.displays?.isWatching == false)
        r.appWillTerminate()
    }
}

@Suite struct ResolutionChoicesTests {
    private typealias Mode = ResolutionChoices.Mode

    /// Scaled modes like a 14 inch MacBook Pro's (3024 × 1964 panel), plus the 1x copies.
    private var laptop: [Mode] {
        let scaled: [(Int, Int)] = [(800, 520), (1024, 665), (1147, 745), (1312, 848), (1352, 878), (1512, 982), (1728, 1117)]
        var modes = scaled.enumerated().map { i, s in Mode(id: Int32(i), width: s.0, height: s.1, pixelWidth: s.0 * 2, pixelHeight: s.1 * 2) }
        modes += scaled.enumerated().map { i, s in Mode(id: Int32(50 + i), width: s.0, height: s.1, pixelWidth: s.0, pixelHeight: s.1) }
        modes.append(Mode(id: 99, width: 3024, height: 1964, pixelWidth: 3024, pixelHeight: 1964))
        // Same size at a lower refresh rate, and one not for the desktop.
        modes.append(Mode(id: 40, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 50))
        modes.append(Mode(id: 41, width: 1600, height: 900, pixelWidth: 3200, pixelHeight: 1800, usable: false))
        return modes
    }

    @Test func aLaptopGetsFiveScaledSizesWithTheDefault() {
        let c = ResolutionChoices.choices(laptop, current: laptop[5])
        // Six sizes in the panel's shape (800 is too small): both ends, the default, two spread between.
        #expect(c.map(\.width) == [1024, 1147, 1352, 1512, 1728])
        #expect(c.first { $0.isDefault }?.width == 1512)
        #expect(c.first { $0.width == 1512 }?.id == 5)   // the mode in use, not the 50 Hz one
        #expect(c.allSatisfy { Double($0.width) / Double($0.height) > 1.53 && Double($0.width) / Double($0.height) < 1.56 })
    }

    @Test func manySizesAreSpreadFromLargerTextToMoreSpace() {
        let widths = [1280, 1440, 1600, 1760, 1920, 2048, 2304, 2560, 2880, 3008]
        let modes = widths.enumerated().map { i, w in
            Mode(id: Int32(i), width: w, height: w * 9 / 16, pixelWidth: w * 2, pixelHeight: w * 9 / 8)
        } + [Mode(id: 90, width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160)]
        let current = modes[7]
        let c = ResolutionChoices.choices(modes, current: current)
        #expect(c.count == 5)
        #expect(c.first?.width == 1280 && c.last?.width == 3008)
        #expect(c.contains { $0.width == 2560 })
        #expect(c.contains { $0.isDefault && $0.width == 1920 })
        #expect(c.map(\.width) == c.map(\.width).sorted())
    }

    @Test func aMonitorWithoutScaledSizesGetsItsPlainOnes() {
        let modes = [(1920, 1080), (1680, 945), (1280, 720), (1024, 576), (800, 450), (1280, 1024)].enumerated().map { i, s in
            Mode(id: Int32(i), width: s.0, height: s.1, pixelWidth: s.0, pixelHeight: s.1)
        }
        let c = ResolutionChoices.choices(modes, current: modes[0])
        #expect(c.map(\.width) == [1024, 1280, 1680, 1920])
        #expect(c.first { $0.isDefault }?.width == 1920)
        #expect(ResolutionChoices.choices([], current: nil).isEmpty)
    }
}
