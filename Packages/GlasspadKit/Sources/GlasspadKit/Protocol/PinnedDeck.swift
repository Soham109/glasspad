import Foundation

// Actions on the phone is one screen: the front app's best buttons on top, then "Pinned",
// one grid of the user's favourites. These helpers shape a `DeckLayout` for that screen
// without changing what the Mac stores: Pinned is the built-in "My Buttons" page, and the
// per-app buttons are the pages linked to apps, exactly as before.

/// One tile in the front-app section: a button from the app's linked page, or a macro from
/// the app's macro profile.
public enum FrontAppItem: Equatable, Sendable, Identifiable {
    case button(DeckButton)
    case macro(MacroSummary)

    /// Stable key, used to remember which items show and in what order.
    public var id: String {
        switch self {
        case .button(let b): "b:\(b.id.uuidString)"
        case .macro(let m): "m:\(m.id.uuidString)"
        }
    }
}

public enum PinnedDeck {
    /// The built-in page that holds Pinned (called "My Buttons" on older phones).
    public static let pinnedPageID = UUID(uuidString: "6D61632D-0000-4000-8000-000000000002")!
    /// The built-in page of Mac controls that older phones showed as its own tab.
    public static let macPageID = UUID(uuidString: "6D61632D-0000-4000-8000-000000000001")!
    /// How many buttons the front-app section shows at most.
    public static let frontAppLimit = 8
    /// How many it shows before the user picks: the first few, so it stays calm.
    public static let frontAppDefaultCount = 6
    /// Above this many Pinned tiles, Actions suggests tidying up once.
    public static let tidyThreshold = 12

    /// What Pinned starts with on a new setup, and what "Reset to Defaults" puts back: six Mac
    /// controls people use every day that have no easy shortcut of their own (Do Not Disturb and
    /// Split Screen have none at all, Dark Mode lives in System Settings). Everything else is one
    /// tap away in the Library. Fresh ids each time.
    public static func essentials() -> [DeckButton] {
        func system(_ a: DeckSystemAction) -> DeckButton {
            DeckButton(title: a.title, symbol: a.symbol, action: .system(a), color: a.color)
        }
        return [
            DeckButton(title: "Screenshot", symbol: "camera.viewfinder", action: .screenshot(DeckScreenshot(area: .fullScreen)),
                       color: "#0A84FF"),
            system(.doNotDisturb),
            system(.windowSplit),
            system(.lockScreen),
            system(.mute),
            system(.toggleDarkMode),
        ]
    }

    /// The layout with Pinned replaced by the essentials. Folders and buttons that were in
    /// Pinned go; pages linked to apps stay. Used only when the user asks for it.
    public static func resetPinned(_ layout: DeckLayout) -> DeckLayout {
        var (l, i) = ensuringPinned(layout)
        l.pages[i].buttons = essentials()
        return l
    }

    /// Index of the Pinned page, if the layout has one.
    public static func pinnedIndex(in layout: DeckLayout) -> Int? {
        layout.pages.firstIndex { $0.id == pinnedPageID }
    }

    /// The Pinned buttons (top level; folders keep their children).
    public static func pinned(in layout: DeckLayout) -> [DeckButton] {
        pinnedIndex(in: layout).map { layout.pages[$0].buttons } ?? []
    }

    /// The layout with a Pinned page, and that page's index.
    public static func ensuringPinned(_ layout: DeckLayout) -> (DeckLayout, Int) {
        if let i = pinnedIndex(in: layout) { return (layout, i) }
        var l = layout
        l.pages.append(DeckPage(id: pinnedPageID, title: "Pinned", symbol: "pin", buttons: []))
        return (l, l.pages.count - 1)
    }

    /// Adds a button at the end of Pinned (or inside a Pinned folder).
    public static func pin(_ button: DeckButton, in layout: DeckLayout, folder: UUID? = nil) -> DeckLayout {
        var (l, i) = ensuringPinned(layout)
        l.add(button, page: i, folder: folder)
        return l
    }

    /// True when a button doing exactly this is already somewhere in Pinned (folders included).
    public static func isPinned(_ action: DeckAction, in layout: DeckLayout) -> Bool {
        pinned(in: layout).flattenedDeck.contains { $0.action == action }
    }

    /// A Pinned tile that runs this macro, looking like the macro.
    public static func button(for macro: MacroSummary) -> DeckButton {
        DeckButton(title: macro.name, symbol: macro.symbol, action: .runMacro(id: macro.id), color: macro.color)
    }

    /// Brings a layout to the one-screen shape without losing anything:
    /// - Pinned exists (a layout from an older Mac with one flat page uses that page's buttons).
    /// - Every page not linked to an app, other than Pinned, becomes a folder at the end of
    ///   Pinned with the page's name, symbol and buttons (the Mac page included). Empty pages
    ///   are dropped, since they hold nothing.
    /// - On a layout from before Actions (it still has the Mac page, or no Pinned page), every
    ///   macro that no button runs yet gets a Pinned tile, because the old My Buttons page listed
    ///   every macro under its buttons. A new setup is left alone: its macros live in the Library.
    /// Pages linked to apps stay as they are: they are the front-app buttons.
    /// Running it again changes nothing (folders keep their ids, macros are found by id).
    public static func migrated(_ layout: DeckLayout, macros: [MacroSummary]) -> DeckLayout {
        var l = layout
        let legacy = l.pages.contains { $0.id == macPageID } || pinnedIndex(in: l) == nil
        let loose = l.pages.filter { $0.id != pinnedPageID && ($0.appBundleIDs ?? []).isEmpty }
        var pinned: DeckPage
        var folders: [DeckPage] = loose
        if let i = pinnedIndex(in: l) {
            pinned = l.pages[i]
        } else if let first = loose.first(where: { $0.id != macPageID }) {
            // An older Mac's single flat page is Pinned itself, not a folder inside it.
            pinned = DeckPage(id: pinnedPageID, title: "Pinned", symbol: "pin", buttons: first.buttons)
            folders.removeAll { $0.id == first.id }
        } else {
            pinned = DeckPage(id: pinnedPageID, title: "Pinned", symbol: "pin", buttons: [])
        }
        for page in folders where !page.buttons.isEmpty {
            pinned.buttons.append(DeckButton(id: page.id, title: page.title,
                                             symbol: page.symbol ?? (page.id == macPageID ? "macbook" : "folder.fill"),
                                             action: .folder, color: "#8E8E93", children: page.buttons))
        }
        let runs = Set((l.pages.flatMap(\.buttons) + pinned.buttons).flattenedDeck.compactMap { b -> UUID? in
            if case .runMacro(let id) = b.action { return id }
            return nil
        })
        for macro in macros where legacy && !runs.contains(macro.id) {
            pinned.buttons.append(button(for: macro))
        }
        let movedIDs = Set(loose.map(\.id))
        l.pages.removeAll { movedIDs.contains($0.id) || $0.id == pinnedPageID }
        l.pages.insert(pinned, at: 0)
        return l
    }

    /// What the front-app section shows: the linked page's buttons, then the profile's macros,
    /// at most `limit`. `picks` (keys from `FrontAppItem.id`) is the user's own choice and
    /// order; keys that no longer exist are skipped, and new items are not added on their own.
    public static func frontAppItems(buttons: [DeckButton], macros: [MacroSummary], picks: [String]?,
                                     limit: Int = frontAppLimit) -> [FrontAppItem] {
        let all = allFrontAppItems(buttons: buttons, macros: macros)
        guard let picks else { return Array(all.prefix(min(limit, frontAppDefaultCount))) }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Array(picks.compactMap { byID[$0] }.prefix(limit))
    }

    /// Every candidate for the front-app section, in the default order.
    public static func allFrontAppItems(buttons: [DeckButton], macros: [MacroSummary]) -> [FrontAppItem] {
        var seen = Set<String>()
        return (buttons.map(FrontAppItem.button) + macros.map(FrontAppItem.macro)).filter { seen.insert($0.id).inserted }
    }
}
