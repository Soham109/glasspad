import Foundation

extension LayoutLibrary {
    /// Layouts whose name contains `text`, ignoring case and accents, for Siri ("Open Couch").
    /// An exact name comes first; the rest keep the person's order. Empty text matches all.
    public func layouts(matching text: String) -> [ScreenLayout] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return layouts }
        let found = layouts.filter { $0.name.localizedStandardContains(query) }
        let exact = found.filter { $0.name.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        return exact + found.filter { !exact.contains($0) }
    }
}
