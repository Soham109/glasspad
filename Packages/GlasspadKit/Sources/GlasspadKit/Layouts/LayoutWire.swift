import Foundation

/// What to tell the Mac when several modes share the screen.
///
/// The Mac follows one screen at a time (`modeSelected`): it streams now playing only for
/// Media, pushes Dock changes only for Dock, and the frontmost app only for Dock and Deck.
/// So a layout names the pane whose live data needs the Mac's attention most, then asks for
/// the rest directly. A media request starts the now playing stream whatever screen the Mac
/// thinks is showing, so Media can share with any other mode. Remote gets now playing and the
/// frontmost app by itself. A Dock pane the Mac does not follow is refreshed by asking again.
/// After `modeSelected`, `modesShown` names every pane, so a Mac from Oct 2026 on pushes the
/// frontmost app and Dock changes to whichever panes want them; an older Mac drops it.
public struct LayoutWirePlan: Equatable, Sendable {
    /// The screen to report with `modeSelected`.
    public var primary: GlasspadMode
    /// Also ask for now playing, after `modeSelected` (which would otherwise stop it).
    public var requestsMedia: Bool
    /// A Dock pane shares the screen with a mode the Mac follows instead, so the Mac does not
    /// push Dock changes: the phone asks for the list again now and then while it shows.
    /// Works with every Mac build, since it is the same request a Dock screen makes.
    public var refreshesDock: Bool
    /// Every pane's mode, sent as `modesShown` after `modeSelected` when more than one shows.
    public var shown: [GlasspadMode]?

    /// Most demanding first. Present keeps the laser on, Dock wants its list pushed, Deck the
    /// frontmost app, Macros its list; Media comes after them because a request covers it.
    static let priority: [GlasspadMode] = [.present, .dock, .remote, .deck, .macros, .media, .keys, .clipboard, .trackpad]

    public init(modes: [GlasspadMode]) {
        let primary = Self.priority.first(where: modes.contains) ?? modes.first ?? .trackpad
        self.primary = primary
        // Remote shows now playing too, so it needs the request when it is not the primary.
        requestsMedia = primary != .media && primary != .remote && (modes.contains(.media) || modes.contains(.remote))
        refreshesDock = primary != .dock && modes.contains(.dock)
        var unique: [GlasspadMode] = []
        for m in modes where !unique.contains(m) { unique.append(m) }
        shown = unique.count > 1 ? unique : nil
    }
}
