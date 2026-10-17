import AppIntents
import GlasspadKit

// "Open Glasspad Mode" and "Open Glasspad Layout": open the app on one screen. With them a
// Focus, an NFC tag, the charger or the Action button can bring up the right screen.

/// The modes Shortcuts offers. Raw values are `AppMode`'s, so saved shortcuts keep working.
/// Pinned and Macros are left out: they are parts of Actions.
enum GlasspadModeOption: String, AppEnum {
    case trackpad, keys, media, dock, actions, present, remote, displays, clipboard, clock, nowPlaying, calendar

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Glasspad Mode"

    // Titles and symbols as AppMode has them (Shortcuts needs them written out here).
    static let caseDisplayRepresentations: [GlasspadModeOption: DisplayRepresentation] = [
        .trackpad: DisplayRepresentation(title: "Trackpad", image: .init(systemName: "hand.point.up.left.fill")),
        .keys: DisplayRepresentation(title: "Keyboard", image: .init(systemName: "keyboard.fill")),
        .media: DisplayRepresentation(title: "Media", image: .init(systemName: "play.circle.fill")),
        .dock: DisplayRepresentation(title: "Dock", image: .init(systemName: "dock.rectangle")),
        .actions: DisplayRepresentation(title: "Actions", image: .init(systemName: "bolt.fill")),
        .present: DisplayRepresentation(title: "Present", image: .init(systemName: "play.rectangle.fill")),
        .remote: DisplayRepresentation(title: "Remote", image: .init(systemName: "appletvremote.gen4.fill")),
        .displays: DisplayRepresentation(title: "Displays", image: .init(systemName: "display.2")),
        .clipboard: DisplayRepresentation(title: "Clipboard", image: .init(systemName: "doc.on.clipboard.fill")),
        .clock: DisplayRepresentation(title: "Clock", image: .init(systemName: "clock.fill")),
        .nowPlaying: DisplayRepresentation(title: "Now Playing", image: .init(systemName: "music.note")),
        .calendar: DisplayRepresentation(title: "Calendar", image: .init(systemName: "calendar")),
    ]

    var mode: AppMode {
        switch self {
        case .trackpad: .trackpad
        case .keys: .keys
        case .media: .media
        case .dock: .dock
        case .actions: .actions
        case .present: .present
        case .remote: .remote
        case .displays: .displays
        case .clipboard: .clipboard
        case .clock: .clock
        case .nowPlaying: .nowPlaying
        case .calendar: .calendar
        }
    }
}

struct OpenModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Glasspad Mode"
    static let description = IntentDescription("Opens Glasspad on the mode you choose.")
    static let openAppWhenRun = true

    @Parameter(title: "Mode")
    var mode: GlasspadModeOption

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$mode) in Glasspad")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openFromShortcut(mode.mode)
        return .result()
    }
}

// MARK: - Layouts

/// One of the person's saved layouts as Shortcuts sees it.
struct LayoutEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Glasspad Layout"
    static let defaultQuery = LayoutQuery()

    let id: UUID
    let name: String
    /// "Trackpad and Actions".
    let panes: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(panes)", image: .init(systemName: symbol))
    }

    init(_ layout: ScreenLayout) {
        id = layout.id
        name = layout.name
        panes = layout.paneSummary
        symbol = layout.symbol(landscape: false)
    }
}

struct LayoutQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [LayoutEntity] {
        identifiers.compactMap { LayoutStore.shared.layout($0) }.map(LayoutEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [LayoutEntity] {
        LayoutStore.shared.layouts.map(LayoutEntity.init)
    }

    /// Lets Siri find "Couch" by name.
    @MainActor
    func entities(matching string: String) async throws -> [LayoutEntity] {
        LayoutStore.shared.library.layouts(matching: string).map(LayoutEntity.init)
    }
}

struct OpenLayoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Glasspad Layout"
    static let description = IntentDescription("Opens Glasspad on one of your layouts.")
    static let openAppWhenRun = true

    @Parameter(title: "Layout")
    var layout: LayoutEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$layout) in Glasspad")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Read again: it may have been changed or deleted since the shortcut was made.
        guard let saved = LayoutStore.shared.layout(layout.id) else { throw IntentProblem("That layout no longer exists.") }
        AppRouter.shared.openFromShortcut(layout: saved)
        return .result()
    }
}

/// A plain sentence Shortcuts and Siri show when an action could not do its job.
struct IntentProblem: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
