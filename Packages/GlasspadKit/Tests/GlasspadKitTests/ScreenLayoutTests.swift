import CoreGraphics
import Foundation
import Testing
@testable import GlasspadKit

@Suite struct DividerMathTests {
    /// iPhone 18 Pro: 874 pt wide in landscape, 874 pt tall in portrait.
    let length = 874.0

    @Test func snapsToThirdsAndMiddleWhenNear() {
        #expect(DividerMath.settle(length / 2 + 15, length: length) == 0.5)
        #expect(DividerMath.settle(length / 3 - 20, length: length) == 1.0 / 3)
        #expect(DividerMath.settle(length * 2 / 3 + 10, length: length) == 2.0 / 3)
    }

    @Test func staysWhereReleasedAwayFromSnaps() {
        let free = DividerMath.settle(length * 0.42, length: length)
        #expect(abs(free - 0.42) < 0.0001)
        #expect(DividerMath.nearestSnap(length * 0.42, length: length) == nil)
    }

    @Test func neverLeavesAPaneSmallerThanTheMinimum() {
        let s = DividerMath.settle(80, length: length)
        #expect(s * length == DividerMath.minimumPane)
        let e = DividerMath.settle(length - 70, length: length)
        #expect(abs((1 - e) * length - DividerMath.minimumPane) < 0.0001)
    }

    @Test func foldsOnlyWhenDraggedWellPastTheEdge() {
        #expect(DividerMath.settle(DividerMath.minimumPane - DividerMath.foldDistance + 1, length: length) != 0)
        #expect(DividerMath.settle(DividerMath.minimumPane - DividerMath.foldDistance - 1, length: length) == 0)
        #expect(DividerMath.settle(-40, length: length) == 0)
        #expect(DividerMath.settle(length + 10, length: length) == 1)
        #expect(DividerMath.wouldFold(-40, length: length))
        #expect(!DividerMath.wouldFold(length / 2, length: length))
    }

    @Test func trackingResistsPastTheMinimumButNotFromAFold() {
        let free = DividerMath.tracking(400, length: length)
        #expect(abs(free * length - 400) < 0.0001)
        let resisted = DividerMath.tracking(0, length: length) * length
        #expect(resisted > 0 && resisted < DividerMath.minimumPane)
        // Far past the edge the line keeps moving less and less, and stays on screen.
        let further = DividerMath.tracking(-500, length: length) * length
        #expect(further < resisted && further >= 0)
        // Pulled out of a folded edge: no jump on first touch.
        #expect(DividerMath.tracking(4, length: length, resists: false) * length == 4)
    }

    @Test func tinySpansStillSettle() {
        #expect(DividerMath.settle(50, length: 100) == 0.5)
        #expect(DividerMath.settle(5, length: 0) == 0.5)
    }
}

@Suite struct ScreenLayoutTests {
    @Test func cleansPanes() {
        #expect(ScreenLayout(name: "A", panes: []).panes == ["trackpad"])
        #expect(ScreenLayout(name: "A", panes: ["media", "media", "", "dock", "keys", "actions"]).panes == ["media", "dock", "keys"])
        #expect(ScreenLayout(name: "A", panes: ["dock"], split: 7).split == 1)
        #expect(ScreenLayout(name: "A", panes: ["dock"], split: .nan).split == 0.5)
    }

    @Test func choosingAModeAlreadyShownSwapsInsteadOfRepeating() {
        var l = ScreenLayout(name: "A", panes: ["trackpad", "media", "actions"])
        l.setMode("actions", at: 0)
        #expect(l.panes == ["actions", "media", "trackpad"])
        l.setMode("keys", at: 1)
        #expect(l.panes == ["actions", "keys", "trackpad"])
    }

    @Test func addAndRemovePanes() {
        var l = ScreenLayout(name: "A", panes: ["trackpad"])
        let added = l.addPane(candidates: ["trackpad", "media", "dock"])
        #expect(added)
        #expect(l.panes == ["trackpad", "media"])
        let third = l.addPane("trackpad", candidates: ["dock"])   // already shown, so the next candidate
        #expect(third)
        #expect(l.panes == ["trackpad", "media", "dock"])
        let full = l.addPane(candidates: ["keys"])
        #expect(!full)
        l.split = 0.7
        l.removePane(at: 0)
        #expect(l.panes == ["media", "dock"])
        l.removePane(at: 0)
        l.removePane(at: 0)
        #expect(l.panes == ["dock"])
    }

    @Test func automaticSplitsSideBySideInLandscapeAndStackedInPortrait() {
        let l = ScreenLayout(name: "A", panes: ["trackpad", "actions"], split: 0.5)
        let wide = l.arrangement(in: CGSize(width: 874, height: 402), gap: 10)
        #expect(wide.panes.map(\.rect) == [CGRect(x: 0, y: 0, width: 432, height: 402), CGRect(x: 442, y: 0, width: 432, height: 402)])
        #expect(wide.dividers.first?.sideBySide == true)
        let tall = l.arrangement(in: CGSize(width: 402, height: 874), gap: 10)
        #expect(tall.panes.map(\.rect) == [CGRect(x: 0, y: 0, width: 402, height: 432), CGRect(x: 0, y: 442, width: 402, height: 432)])
        var stacked = l
        stacked.direction = .stacked
        #expect(stacked.arrangement(in: CGSize(width: 874, height: 402), gap: 10).dividers.first?.sideBySide == false)
    }

    @Test func threePanesNestTheOtherWay() {
        let l = ScreenLayout(name: "Desk", panes: ["trackpad", "media", "actions"], split: 0.5, innerSplit: 0.5)
        let a = l.arrangement(in: CGSize(width: 810, height: 410), gap: 10)
        #expect(a.panes.count == 3)
        #expect(a.panes[0].rect == CGRect(x: 0, y: 0, width: 400, height: 410))
        #expect(a.panes[1].rect == CGRect(x: 410, y: 0, width: 400, height: 200))
        #expect(a.panes[2].rect == CGRect(x: 410, y: 210, width: 400, height: 200))
        #expect(a.dividers.map(\.sideBySide) == [true, false])
        // Upright: three rows, never two narrow columns.
        let tall = l.arrangement(in: CGSize(width: 400, height: 830), gap: 10)
        #expect(tall.dividers.map(\.sideBySide) == [false, false])
        #expect(tall.panes.allSatisfy { $0.rect.width == 400 })
        // Stacked while sideways: a wide strip along the bottom splits side by side.
        var stacked = l
        stacked.direction = .stacked
        #expect(stacked.arrangement(in: CGSize(width: 874, height: 402), gap: 10).dividers.map(\.sideBySide) == [false, true])
    }

    @Test func foldedPanesLeaveTheirLineAtTheEdge() {
        var l = ScreenLayout(name: "A", panes: ["trackpad", "media", "actions"], split: 0)
        let a = l.arrangement(in: CGSize(width: 800, height: 400), gap: 10)
        #expect(a.panes.map(\.index) == [1, 2])
        #expect(a.dividers[0].rect == CGRect(x: 0, y: 0, width: 10, height: 400))
        #expect(l.visibleModes == ["media", "actions"])
        l.split = 0.5
        l.innerSplit = 1
        #expect(l.visibleModes == ["trackpad", "media"])
        l.split = 1
        #expect(l.visibleModes == ["trackpad"])
    }
}

@Suite struct LayoutLibraryTests {
    @Test func roundTrips() throws {
        let layout = ScreenLayout(name: "Desk", panes: ["trackpad", "media"], direction: .stacked, split: 0.6)
        let library = LayoutLibrary(layouts: [layout], activeID: layout.id)
        let back = try JSONDecoder().decode(LayoutLibrary.self, from: JSONEncoder().encode(library))
        #expect(back == library)
    }

    @Test func readsOlderAndDamagedData() throws {
        let id = UUID()
        let json = """
        {"layouts": [
            {"id": "\(id.uuidString)", "name": "Old", "panes": ["trackpad", "media"]},
            {"id": "not a uuid", "name": "Broken id", "panes": ["dock"], "direction": "diagonal", "split": "wide"},
            {"name": "No panes"},
            42,
            {"id": "\(id.uuidString)", "name": "Same id again", "panes": ["keys"]}
        ], "activeID": "\(UUID().uuidString)"}
        """
        let library = try JSONDecoder().decode(LayoutLibrary.self, from: Data(json.utf8))
        #expect(library.version == LayoutLibrary.currentVersion)
        #expect(library.layouts.map(\.name) == ["Old", "Broken id", "No panes"])
        #expect(library.layouts[0].id == id)
        #expect(library.layouts[0].direction == .automatic && library.layouts[0].split == 0.5)
        #expect(library.layouts[1].direction == .automatic && library.layouts[1].panes == ["dock"])
        #expect(library.layouts[2].panes == ["trackpad"])
        // The open layout no longer exists.
        #expect(library.activeID == nil)
    }

    @Test func keepsUnknownModesForNewerBuilds() throws {
        let json = #"{"name": "Couch", "panes": ["remote", "media"]}"#
        #expect(try JSONDecoder().decode(ScreenLayout.self, from: Data(json.utf8)).panes == ["remote", "media"])
    }

    @Test func duplicateDeleteMoveAndNames() {
        var library = LayoutLibrary()
        let a = ScreenLayout(name: "Desk", panes: ["trackpad"])
        let b = ScreenLayout(name: "Couch", panes: ["media"])
        library.save(a)
        library.save(b)
        let copy = library.duplicate(a.id)
        #expect(library.layouts.map(\.name) == ["Desk", "Desk Copy", "Couch"])
        #expect(copy?.id != a.id)
        let second = library.duplicate(a.id)
        #expect(second?.name == "Desk Copy 2")
        library.move(fromOffsets: [3], toOffset: 0)
        #expect(library.layouts.first?.name == "Couch")
        library.activeID = b.id
        library.delete(b.id)
        #expect(library.activeID == nil && library.layouts.count == 3)
        #expect(library.uniqueName("Desk") == "Desk 2")
        #expect(library.uniqueName("Desk", ignoring: a.id) == "Desk")
        var renamed = a
        renamed.name = "Studio"
        library.save(renamed)
        #expect(library.layout(a.id)?.name == "Studio" && library.layouts.count == 3)
    }

    @Test func newInstallsStartWithAFewLayouts() {
        let all = LayoutLibrary.starter()
        #expect(all.layouts.map(\.name) == ["Desk", "Type", "Listen", "Couch"])
        #expect(all.activeID == nil)
        // A build without Remote leaves Couch out rather than showing a broken pane.
        #expect(LayoutLibrary.starter(known: { $0 != "remote" }).layouts.map(\.name) == ["Desk", "Type", "Listen"])
    }

    @Test func templatesAreValid() {
        let ids = LayoutTemplate.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
        for t in LayoutTemplate.builtIn {
            let l = t.makeLayout()
            #expect(l.panes == t.panes, "\(t.id)")
            #expect((1...ScreenLayout.maxPanes).contains(l.panes.count))
        }
    }
}

@Suite struct LayoutWireTests {
    @Test func picksTheModeTheMacMustFollowAndAsksForMediaSeparately() {
        #expect(LayoutWirePlan(modes: [.trackpad]) == LayoutWirePlan(modes: [.trackpad]))
        #expect(LayoutWirePlan(modes: [.trackpad]).primary == .trackpad)
        let tm = LayoutWirePlan(modes: [.trackpad, .media])
        #expect(tm.primary == .media && !tm.requestsMedia)
        let dm = LayoutWirePlan(modes: [.media, .dock])
        #expect(dm.primary == .dock && dm.requestsMedia)
        #expect(LayoutWirePlan(modes: [.trackpad, .deck, .media]).primary == .deck)
        #expect(LayoutWirePlan(modes: [.keys, .present]).primary == .present)
        #expect(LayoutWirePlan(modes: []).primary == .trackpad)
        let couch = LayoutWirePlan(modes: [.remote, .trackpad, .media])
        #expect(couch.primary == .remote && !couch.requestsMedia)
    }
}
