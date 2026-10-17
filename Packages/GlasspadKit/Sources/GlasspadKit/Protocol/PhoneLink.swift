import Foundation

extension DeckAction {
    /// A Pinned button that acts on the iPhone itself: a link of Glasspad's own
    /// (`glasspad://mode/clipboard` opens Clipboard). The phone opens it and the Mac is never
    /// asked, so it needs no new action and older builds keep it as an ordinary link.
    public var phoneLink: URL? {
        guard case .openURL(let s) = self, let url = URL(string: s), url.scheme?.lowercased() == "glasspad" else { return nil }
        return url
    }
}
