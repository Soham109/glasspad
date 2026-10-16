import Foundation

/// What to tell the Mac when several modes share the screen.
///
/// The Mac follows one screen at a time (`modeSelected`): it streams now playing only for
/// Media, pushes Dock changes only for Dock, and the frontmost app only for Dock and Deck.
/// So a layout names the pane whose live data needs the Mac's attention most, then asks for
/// the rest directly. A media request starts the now playing stream whatever screen the Mac
/// thinks is showing, so Media can share with any other mode. Remote gets now playing and the
/// frontmost app by itself.
public struct LayoutWirePlan: Equatable, Sendable {
    /// The screen to report with `modeSelected`.
    public var primary: GlasspadMode
    /// Also ask for now playing, after `modeSelected` (which would otherwise stop it).
    public var requestsMedia: Bool

    /// Most demanding first. Present keeps the laser on, Dock wants its list pushed, Deck the
    /// frontmost app, Macros its list; Media comes after them because a request covers it.
    static let priority: [GlasspadMode] = [.present, .dock, .remote, .deck, .macros, .media, .keys, .clipboard, .trackpad]

    public init(modes: [GlasspadMode]) {
        let primary = Self.priority.first(where: modes.contains) ?? modes.first ?? .trackpad
        self.primary = primary
        requestsMedia = primary != .media && primary != .remote && modes.contains(.media)
    }
}
