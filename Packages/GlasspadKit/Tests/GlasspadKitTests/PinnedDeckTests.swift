import Foundation
import Testing
@testable import GlasspadKit

@Suite struct PinnedDeckTests {
    private func b(_ t: String, _ a: DeckAction = .system(.lockScreen)) -> DeckButton { DeckButton(title: t, symbol: "bolt", action: a) }
    private func macro(_ n: String) -> MacroSummary {
        MacroSummary(id: UUID(), name: n, symbol: "wand.and.stars", color: "#12A594", stepCount: 2, usesScripts: false)
    }

    /// The layout an existing user has: Mac page, My Buttons with a folder, an own page, an empty
    /// page and a page linked to Safari.
    private func oldLayout() -> (DeckLayout, [DeckButton]) {
        let folder = DeckButton(title: "Work", symbol: "folder.fill", action: .folder, children: [b("Slack"), b("Mail")])
        let mine = [b("Safari", .openApp(bundleID: "com.apple.Safari")), folder]
        let mac = [b("Lock"), b("Mute", .system(.mute))]
        let own = [b("Docs", .openURL("https://example.com"))]
        let linked = [b("New Tab", .keystroke(Keystroke(key: .character("t"), modifiers: [.command])))]
        let layout = DeckLayout(pages: [
            DeckPage(id: PinnedDeck.macPageID, title: "Mac", symbol: "macbook", buttons: mac),
            DeckPage(id: PinnedDeck.pinnedPageID, title: "My Buttons", symbol: "star", buttons: mine),
            DeckPage(title: "Writing", symbol: "pencil", buttons: own),
            DeckPage(title: "Empty", buttons: []),
            DeckPage(title: "Safari", appBundleIDs: ["com.apple.Safari"], buttons: linked),
        ], columns: 4)
        return (layout, mine + mac + own + linked)
    }

    @Test func migrationKeepsEveryButtonAndPutsLoosePagesInPinned() {
        let (old, everything) = oldLayout()
        let macros = [macro("Rename"), macro("Standup")]
        let new = PinnedDeck.migrated(old, macros: macros)

        // Nothing lost: every old button (folders and their children included) is still there, once.
        let before = old.allButtons.map(\.id)
        let after = new.allButtons.map(\.id)
        for id in before { #expect(after.filter { $0 == id }.count == 1) }
        #expect(everything.allSatisfy { new.button(id: $0.id) != nil })

        // Two pages remain: Pinned first, then the page linked to Safari, untouched.
        #expect(new.pages.map(\.id) == [PinnedDeck.pinnedPageID, old.pages[4].id])
        #expect(new.pages[1] == old.pages[4])
        #expect(new.columns == 4)

        // Pinned: its own buttons in order, then each non-empty loose page as a folder, then macros.
        let pinned = PinnedDeck.pinned(in: new)
        #expect(pinned.map(\.title) == ["Safari", "Work", "Mac", "Writing", "Rename", "Standup"])
        #expect(pinned[2].action == .folder && pinned[2].children == old.pages[0].buttons)
        #expect(pinned[3].symbol == "pencil" && pinned[3].children == old.pages[2].buttons)
        #expect(pinned[4].action == .runMacro(id: macros[0].id))
        #expect(pinned[1].children?.map(\.title) == ["Slack", "Mail"])
    }

    @Test func migrationIsIdempotent() {
        let (old, _) = oldLayout()
        let macros = [macro("Rename")]
        let once = PinnedDeck.migrated(old, macros: macros)
        #expect(PinnedDeck.migrated(once, macros: macros) == once)
    }

    @Test func macrosAlreadyOnAButtonAreNotPinnedTwice() {
        let m = macro("Rename")
        let layout = DeckLayout(pages: [DeckPage(title: "Safari", appBundleIDs: ["x"], buttons: [PinnedDeck.button(for: m)])])
        let new = PinnedDeck.migrated(layout, macros: [m])
        #expect(PinnedDeck.pinned(in: new).isEmpty)
    }

    @Test func olderMacFlatPageBecomesPinnedItself() {
        let flat = DeckLayout(pages: [DeckPage(title: "Buttons", buttons: [b("A"), b("B")])])
        let new = PinnedDeck.migrated(flat, macros: [])
        #expect(new.pages.count == 1)
        #expect(new.pages[0].id == PinnedDeck.pinnedPageID)
        #expect(PinnedDeck.pinned(in: new).map(\.title) == ["A", "B"])
    }

    @Test func pinAddsToTheEndAndKnowsWhatIsPinned() {
        let (old, _) = oldLayout()
        var l = PinnedDeck.migrated(old, macros: [])
        #expect(PinnedDeck.isPinned(.system(.mute), in: l))          // inside the Mac folder
        #expect(!PinnedDeck.isPinned(.system(.ejectAll), in: l))
        l = PinnedDeck.pin(b("Eject", .system(.ejectAll)), in: l)
        #expect(PinnedDeck.pinned(in: l).last?.title == "Eject")
        #expect(PinnedDeck.isPinned(.system(.ejectAll), in: l))

        let empty = PinnedDeck.pin(b("X"), in: DeckLayout(pages: []))
        #expect(PinnedDeck.pinned(in: empty).map(\.title) == ["X"])
    }

    @Test func frontAppItemsDefaultToTheFirstEightAndFollowPicks() {
        let buttons = (1...6).map { b("B\($0)") }
        let macros = (1...4).map { macro("M\($0)") }
        let items = PinnedDeck.frontAppItems(buttons: buttons, macros: macros, picks: nil)
        #expect(items.count == 8)
        #expect(items.first == .button(buttons[0]))
        #expect(items.last == .macro(macros[1]))

        let picks = [FrontAppItem.macro(macros[3]).id, "b:gone", FrontAppItem.button(buttons[2]).id]
        let chosen = PinnedDeck.frontAppItems(buttons: buttons, macros: macros, picks: picks)
        #expect(chosen == [.macro(macros[3]), .button(buttons[2])])
        #expect(PinnedDeck.frontAppItems(buttons: buttons, macros: macros, picks: []).isEmpty)
    }
}
