import Foundation
import Testing
@testable import GlasspadKit

@Suite struct PhoneLinkTests {
    @Test func onlyGlasspadLinksStayOnThePhone() {
        #expect(DeckAction.openURL("glasspad://mode/clipboard").phoneLink?.host() == "mode")
        #expect(DeckAction.openURL("Glasspad://mode/clipboard").phoneLink != nil)
        #expect(DeckAction.openURL("https://apple.com").phoneLink == nil)
        #expect(DeckAction.openURL("x-apple.systempreferences:com.apple.wifi-settings-extension").phoneLink == nil)
        #expect(DeckAction.openURL("").phoneLink == nil)
        #expect(DeckAction.openApp(bundleID: "glasspad").phoneLink == nil)
    }

    @Test func aClipboardButtonSurvivesTheMacsDeckFile() throws {
        // Stored on the Mac as an ordinary link, read back the same by this build.
        let button = DeckButton(title: "Clipboard", symbol: "doc.on.clipboard.fill", action: .openURL("glasspad://mode/clipboard"))
        let back = try JSONDecoder().decode(DeckButton.self, from: JSONEncoder().encode(button))
        #expect(back == button)
        #expect(back.action.isSupported)
    }

    @Test func flippingTwiceComesBack() {
        var history = BackAndForth<String>()
        #expect(history.previous == nil)
        history.moved(from: "trackpad", to: "keys")
        #expect(history.previous == "trackpad")
        // The swipe: back to Trackpad, and Keyboard becomes the one to flip to.
        history.moved(from: "keys", to: "trackpad")
        #expect(history.previous == "keys")
        // Showing the screen already there is not a move.
        history.moved(from: "trackpad", to: "trackpad")
        #expect(history.previous == "keys")
        history.moved(from: "trackpad", to: "media")
        #expect(history.previous == "trackpad")
    }
}
