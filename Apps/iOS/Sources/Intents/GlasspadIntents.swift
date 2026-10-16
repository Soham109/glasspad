import AppIntents
import GlasspadKit
import UIKit

// Siri and Shortcuts actions. Each one connects to the paired Mac if needed (the app runs
// in the background for a few seconds), sends one message and lets go.

struct OpenMissionControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Mission Control"
    static let description = IntentDescription("Shows Mission Control on your Mac.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await MacSession.shared.withConnection { session in
            // Control + Up Arrow is the macOS shortcut for Mission Control.
            session.send(.keysKeystroke(Keystroke(key: .special(.up), modifiers: .control)))
        }
        return .result(dialog: "Mission Control is open.")
    }
}

struct PlayPauseMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause Mac"
    static let description = IntentDescription("Plays or pauses what is playing on your Mac.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await MacSession.shared.withConnection { $0.send(.mediaCommand(.playPause)) }
        return .result()
    }
}

struct NextTrackMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track on Mac"
    static let description = IntentDescription("Skips to the next track on your Mac.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await MacSession.shared.withConnection { $0.send(.mediaCommand(.nextTrack)) }
        return .result()
    }
}

struct SendClipboardToMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Clipboard to Mac"
    static let description = IntentDescription("Puts text on your Mac's clipboard. Leave Text empty to send what is copied on this iPhone.")

    @Parameter(title: "Text")
    var text: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$text) to Mac clipboard")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let content: ClipboardContent
        if let text, !text.isEmpty {
            content = .text(text)
        } else if let copied = UIPasteboard.general.string, !copied.isEmpty {
            content = .text(copied)
        } else if let image = UIPasteboard.general.image, let png = ClipboardReader.pngData(from: image.pngData() ?? Data()) {
            content = .imagePNG(png)
        } else {
            return .result(dialog: "There is nothing copied on this iPhone.")
        }
        var outcome: ClipboardPushStatus?
        try await MacSession.shared.withConnection { outcome = await $0.pushClipboardConfirmed(content) }
        // Only say it was sent when the Mac said it took it.
        switch outcome {
        case .accepted?: return .result(dialog: "Sent to your Mac's clipboard.")
        case .refused(let reason)?: return .result(dialog: "\(reason)")
        case .waiting?, nil: return .result(dialog: "\(ClipboardPushStatus.noConfirmation)")
        }
    }
}

// MARK: - Deck buttons

/// A Deck button as Shortcuts sees it. The list comes from the Mac and is cached on the phone.
struct DeckButtonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Glasspad Button"
    static let defaultQuery = DeckButtonQuery()

    let id: UUID
    let title: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: symbol))
    }

    init(_ button: DeckButton) {
        id = button.id
        title = button.title
        symbol = button.symbol
    }
}

struct DeckButtonQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [DeckButtonEntity] {
        let buttons = MacSession.shared.deckButtons ?? []
        return identifiers.compactMap { id in buttons.first { $0.id == id }.map(DeckButtonEntity.init) }
    }

    @MainActor
    func suggestedEntities() async throws -> [DeckButtonEntity] {
        var buttons: [DeckButton] = []
        // Ask the Mac for the current list; fall back to the cached one if it is not reachable.
        try? await MacSession.shared.withConnection(timeout: 4) { session in
            buttons = await session.fetchDeckButtons()
        }
        if buttons.isEmpty { buttons = MacSession.shared.deckButtons ?? [] }
        return buttons.map(DeckButtonEntity.init)
    }
}

struct RunDeckButtonIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Glasspad Button"
    static let description = IntentDescription("Runs one of your Glasspad buttons on your Mac.")

    @Parameter(title: "Button")
    var button: DeckButtonEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$button) on Mac")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = button.id
        try await MacSession.shared.withConnection { session in
            session.runDeck(id)
            // Wait briefly for the Mac's answer so a failure can be reported.
            for _ in 0..<30 where session.deckPending.contains(id) {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        if let outcome = MacSession.shared.deckOutcomes[id], !outcome.ok {
            return .result(dialog: "\(button.title) did not work: \(outcome.message ?? "unknown error").")
        }
        return .result(dialog: "Ran \(button.title).")
    }
}

// MARK: - Macros

/// A macro as Shortcuts sees it. The list comes from the Mac and is cached on the phone.
struct MacroEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Macro"
    static let defaultQuery = MacroQuery()

    let id: UUID
    let name: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ macro: MacroSummary) {
        id = macro.id
        name = macro.name
        symbol = macro.symbol
    }
}

struct MacroQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [MacroEntity] {
        let all = MacSession.shared.allMacros ?? []
        return identifiers.compactMap { id in all.first { $0.id == id }.map(MacroEntity.init) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MacroEntity] {
        var macros: [MacroSummary] = []
        try? await MacSession.shared.withConnection(timeout: 4) { session in
            macros = await session.fetchMacros()
        }
        if macros.isEmpty { macros = MacSession.shared.allMacros ?? [] }
        return macros.map(MacroEntity.init)
    }

    /// Lets Siri match "Run macro Rename files" by name.
    @MainActor
    func entities(matching string: String) async throws -> [MacroEntity] {
        let all = MacSession.shared.allMacros ?? []
        return all.filter { $0.name.localizedCaseInsensitiveContains(string) }.map(MacroEntity.init)
    }
}

struct RunMacroIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Macro"
    static let description = IntentDescription("Runs one of your Glasspad macros on your Mac.")

    @Parameter(title: "Macro")
    var macro: MacroEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$macro) on Mac")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = macro.id
        try await MacSession.shared.withConnection(timeout: 8) { session in
            session.runMacro(id)
            // Wait for the run to finish (up to 20 s) so failures and outputs can be reported.
            for _ in 0..<200 {
                if let result = session.macroResult, result.macroID == id { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        guard let result = MacSession.shared.macroResult, result.macroID == id else {
            return .result(dialog: "\(macro.name) is running on your Mac.")
        }
        switch result.outcome {
        case .completed:
            if let output = result.output, !output.isEmpty { return .result(dialog: "\(output)") }
            return .result(dialog: "Ran \(macro.name).")
        case .cancelled, .interruptedByUser:
            return .result(dialog: "\(macro.name) was stopped.")
        case .failed:
            return .result(dialog: "\(macro.name) did not finish: \(result.message ?? "unknown error").")
        }
    }
}

// MARK: - Shortcuts app and Siri phrases

struct GlasspadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenTrackpadIntent(),
                    phrases: ["Open \(.applicationName) trackpad", "Start \(.applicationName)"],
                    shortTitle: "Trackpad", systemImageName: "hand.point.up.left")
        AppShortcut(intent: OpenMissionControlIntent(),
                    phrases: ["Open Mission Control with \(.applicationName)", "\(.applicationName) Mission Control"],
                    shortTitle: "Mission Control", systemImageName: "rectangle.3.group")
        AppShortcut(intent: PlayPauseMacIntent(),
                    phrases: ["Play or pause my Mac with \(.applicationName)", "\(.applicationName) play pause"],
                    shortTitle: "Play/Pause Mac", systemImageName: "playpause")
        AppShortcut(intent: SendClipboardToMacIntent(),
                    phrases: ["Send clipboard to Mac with \(.applicationName)", "\(.applicationName) send clipboard"],
                    shortTitle: "Send Clipboard", systemImageName: "doc.on.clipboard")
        AppShortcut(intent: RunMacroIntent(),
                    phrases: ["Run a macro with \(.applicationName)", "Run \(\.$macro) with \(.applicationName)"],
                    shortTitle: "Run Macro", systemImageName: "wand.and.stars")
        AppShortcut(intent: RunDeckButtonIntent(),
                    phrases: ["Run a button with \(.applicationName)"],
                    shortTitle: "Run Glasspad Button", systemImageName: "square.grid.2x2")
    }
}
