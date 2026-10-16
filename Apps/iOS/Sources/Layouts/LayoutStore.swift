import Foundation
import GlasspadKit
import Observation
import UIKit

/// The person's split-screen layouts, saved on the phone. The model and its rules live in
/// GlasspadKit (`ScreenLayout`, `LayoutLibrary`); this keeps them in UserDefaults and
/// connects them to the app's modes.
@MainActor
@Observable
final class LayoutStore {
    static let shared = LayoutStore()

    private(set) var library: LayoutLibrary {
        didSet { save() }
    }

    var layouts: [ScreenLayout] { library.layouts }

    private let defaults: UserDefaults
    private static let key = "screenLayouts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        library = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(LayoutLibrary.self, from: $0) } ?? LayoutLibrary()
    }

    func layout(_ id: UUID) -> ScreenLayout? { library.layout(id) }

    func save(_ layout: ScreenLayout) { library.save(layout) }

    @discardableResult
    func duplicate(_ id: UUID) -> ScreenLayout? { library.duplicate(id) }

    func delete(_ id: UUID) {
        library.delete(id)
        if AppRouter.shared.layoutID == id { AppRouter.shared.show(AppRouter.shared.mode) }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        library.move(fromOffsets: source, toOffset: destination)
    }

    func uniqueName(_ base: String, ignoring id: UUID? = nil) -> String { library.uniqueName(base, ignoring: id) }

    /// The layout on screen, remembered for the next launch.
    var activeID: UUID? {
        get { library.activeID }
        set { if library.activeID != newValue { library.activeID = newValue } }
    }

    /// A divider moved on the live screen. Saved at once, so the screen opens the same way next time.
    func setShare(_ share: Double, level: ScreenLayout.DividerFrame.Level, of id: UUID) {
        guard var layout = library.layout(id) else { return }
        switch level {
        case .main: layout.split = share
        case .inner: layout.innerSplit = share
        }
        library.save(layout)
    }

    /// Templates this build can show (a template naming a mode it does not have stays hidden).
    var templates: [LayoutTemplate] {
        LayoutTemplate.builtIn.filter { $0.panes.allSatisfy { AppMode(rawValue: $0) != nil } }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(library) { defaults.set(data, forKey: Self.key) }
    }
}

extension ScreenLayout {
    /// The panes' modes this build knows. A mode from a newer build shows as the trackpad.
    var modes: [AppMode] { panes.map { AppMode(rawValue: $0) ?? .trackpad } }

    func mode(at index: Int) -> AppMode { AppMode(rawValue: panes[index]) ?? .trackpad }

    /// Modes actually on screen (folded panes left out).
    var shownModes: [AppMode] { visiblePaneIndices.map(mode(at:)) }

    /// A symbol for the pill and lists: two or three panes, the way they split now.
    func symbol(landscape: Bool) -> String {
        let across = direction.isSideBySide(landscape: landscape)
        if visiblePaneIndices.count == 1 { return "rectangle" }
        return across ? "rectangle.split.2x1" : "rectangle.split.1x2"
    }

    /// "Trackpad and Actions", "Trackpad, Media and Actions".
    var paneSummary: String {
        let titles = modes.map(\.title)
        guard titles.count > 1 else { return titles.first ?? "" }
        return titles.dropLast().joined(separator: ", ") + " and " + titles.last!
    }
}

/// Puts the keyboard away, so a sheet over a Keyboard pane gets the whole screen.
@MainActor func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension AppMode {
    /// Modes a pane can show. Deck and Macros only when they are split out of Actions.
    @MainActor static var paneChoices: [AppMode] {
        let visible = AppMode.visible
        return allCases.filter { ($0 != .deck && $0 != .macros) || visible.contains($0) }
    }
}
