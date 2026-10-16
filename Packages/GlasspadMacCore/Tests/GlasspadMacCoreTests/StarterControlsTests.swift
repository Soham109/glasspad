import Foundation
import GlasspadKit
import GlasspadMacros
import Testing
@testable import GlasspadMacCore

@Suite @MainActor struct StarterControlsTests {
    @Test func everyStarterMacControlIsARealDeckAction() {
        var seen = 0
        for macro in StarterLibrary.macros {
            for step in macro.steps {
                guard case .macControl(let id) = step else { continue }
                seen += 1
                #expect(DeckSystemAction(rawValue: id) != nil, "\(macro.name): \(id)")
            }
        }
        #expect(seen > 0)
    }

    @Test func macroStepRunsTheControlThroughTheDeck() async throws {
        let env = FakeDeckEnvironment()
        let deck = DeckMode(env: env, url: tempURL("deck.json"))
        let relay = MacControlRelay()
        relay.perform = { await deck.perform(.system($0)) }
        try await relay.run("windowLeft")
        #expect(env.placed == [.left])
        env.windowFailure = "No window to move"
        await #expect(throws: MacroError.macControlFailed("No window to move")) { try await relay.run("windowRight") }
        await #expect(throws: MacroError.self) { try await relay.run("notAControl") }
    }

    @Test func macControlStepsRoundTripAsJSON() throws {
        let step = MacroStep.macControl("doNotDisturb")
        let data = try JSONEncoder().encode(step)
        #expect(String(decoding: data, as: UTF8.self).contains("\"macControl\""))
        #expect(try JSONDecoder().decode(MacroStep.self, from: data) == step)
        #expect(step.summary == "Do Not Disturb")
        for action in DeckSystemAction.allCases {
            #expect(MacControlName.title(action.rawValue) == action.title, "\(action)")
        }
    }
}
