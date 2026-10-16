import Foundation
import Testing
@testable import GlasspadKit

@Suite struct ModeTypesTests {
    private func roundTrip(_ m: ModeMessage) throws {
        let data = try ControlMessage.mode(m).jsonData()
        #expect(try ControlMessage.from(jsonData: data) == .mode(m))
    }

    @Test func oneDockChoiceMapsBothSwitches() {
        #expect(MacDockHiding(nil) == .never)
        #expect(MacDockHiding(MacDockState(hidden: false, hideWhileConnected: false)) == .never)
        #expect(MacDockHiding(MacDockState(hidden: false, hideWhileConnected: true)) == .whileConnected)
        // Both switches on (an older phone could save that) reads as Always, which it was.
        #expect(MacDockHiding(MacDockState(hidden: true, hideWhileConnected: true)) == .always)
        for choice in MacDockHiding.allCases {
            #expect(MacDockHiding(choice.state) == choice)
        }
        #expect(MacDockHiding.always.state == MacDockState(hidden: true, hideWhileConnected: false))
    }

    @Test func newDockAndDeckMessagesRoundTrip() throws {
        let id = UUID()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 9])
        let folder = DeckButton(title: "Tools", symbol: "folder", action: .folder, color: "#FF9F0A", size: .wide,
                                children: [DeckButton(title: "Shot", symbol: "camera",
                                                      action: .screenshot(DeckScreenshot(area: .frontWindow, sendToPhone: .photos)))])
        let layout = DeckLayout(pages: [
            DeckPage(title: "Main", buttons: [folder,
                                              DeckButton(title: "Lock", symbol: "lock", action: .system(.lockScreen)),
                                              DeckButton(title: "Type", symbol: "text.cursor", action: .typeText("hi")),
                                              DeckButton(title: "Rec", symbol: "record.circle", action: .screenRecording),
                                              DeckButton(title: "Out", symbol: "hifispeaker", action: .setAudioOutput(name: "AirPods")),
                                              DeckButton(title: "Docs", symbol: "folder", action: .openFile(path: "~/Documents")),
                                              DeckButton(title: "Macro", symbol: "wand.and.stars", action: .runMacro(id: id))]),
            DeckPage(title: "Safari", symbol: "safari", appBundleIDs: ["com.apple.Safari"], buttons: []),
        ], columns: 4, allowsShellCommands: false)
        let all: [ModeMessage] = [
            .dockSync(iconKeys: ["com.apple.Safari@123"]),
            .dockAppAction(bundleID: "com.microsoft.Word", action: .quit),
            .dockOpenResult(bundleID: "com.microsoft.Word", ok: false, message: "Not found"),
            .dockOpenResult(bundleID: "com.apple.Notes", ok: true, message: nil),
            .dockCatalogRequest,
            .dockCatalog(apps: [DockApp(bundleID: "a", name: "A", running: false, active: false, iconKey: "a@1")]),
            .dockIconRequest(bundleIDs: ["a", "b"]),
            .dockIcons(apps: [DockApp(bundleID: "a", name: "A", iconPNG: png, running: false, active: false, iconKey: "a@1")]),
            .frontmostApp(bundleID: "com.apple.Safari"),
            .frontmostApp(bundleID: nil),
            .macDockState(MacDockState(hidden: false, hideWhileConnected: true, isHiddenNow: true)),
            .macDockSet(MacDockState(hidden: true, hideWhileConnected: false)),
            .deckLayout(layout),
            .deckSave(layout),
            .deckSaveResult(ok: false, message: "no"),
            .clipboardPushResult(ok: true, message: nil),
            .clipboardPushResult(ok: false, message: "This text is 2.1 MB of text"),
            .clipboardPullRefused(message: "The Mac clipboard is 3.0 MB of text"),
            .deckRunConfirmed(id: id),
            .deckCatalogRequest,
            .deckCatalog(DeckCatalog(audioOutputs: ["Speakers"], shortcuts: ["Focus"])),
            .deckImage(id: id, imageData: png, destination: .clipboard),
            .dockList(apps: [DockApp(bundleID: "x", name: "X", running: true, active: true, iconKey: "x@2",
                                     inDock: true, recent: false, hidden: true)]),
        ]
        for m in all { try roundTrip(m) }
    }

    @Test func clipboardAnswersHaveAPlainWireShape() throws {
        let decoded = try JSONDecoder().decode(ModeMessage.self, from: Data(#"{"t":"clipboardPushResult","ok":false,"message":"m"}"#.utf8))
        #expect(decoded == .clipboardPushResult(ok: false, message: "m"))
        let refused = try JSONDecoder().decode(ModeMessage.self, from: Data(#"{"t":"clipboardPullRefused","message":"r"}"#.utf8))
        #expect(refused == .clipboardPullRefused(message: "r"))
        #expect(ClipboardContent.text("é").byteCount == 2)
        #expect(ClipboardContent.tooLargeMessage(bytes: 3 << 20, holder: "This text")
                == "This text is 3.0 MB of text, more than the 2 MB Glasspad sends at once. Copy a smaller part.")
    }

    @Test func olderDockAppAndDeckButtonStillDecode() throws {
        let app = try JSONDecoder().decode(DockApp.self, from: Data(#"{"bundleID":"a","name":"A","running":true,"active":false}"#.utf8))
        #expect(app.iconKey == nil && app.inDock == nil && app.recent == nil)
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","title":"S","symbol":"safari","action":{"openApp":{"bundleID":"com.apple.Safari"}}}"#
        let button = try JSONDecoder().decode(DeckButton.self, from: Data(json.utf8))
        #expect(button.size == nil && button.children == nil && button.color == nil)
        #expect(button.action == .openApp(bundleID: "com.apple.Safari"))
    }

    @Test func layoutFindsButtonsInsideFolders() {
        let inner = DeckButton(title: "In", symbol: "a", action: .typeText("x"))
        let folder = DeckButton(title: "F", symbol: "folder", action: .folder,
                                children: [DeckButton(title: "Deeper", symbol: "b", action: .folder, children: [inner])])
        let layout = DeckLayout(pages: [DeckPage(title: "P", buttons: [folder])])
        #expect(layout.allButtons.count == 3)
        #expect(layout.button(id: inner.id) == inner)
        #expect(layout.button(id: UUID()) == nil)
    }

    @Test func confirmationOnlyForDestructiveActions() {
        #expect(DeckButton(title: "", symbol: "", action: .system(.emptyTrash)).needsConfirmation)
        #expect(DeckButton(title: "", symbol: "", action: .system(.sleepMac)).needsConfirmation)
        #expect(!DeckButton(title: "", symbol: "", action: .system(.volumeUp)).needsConfirmation)
        #expect(!DeckButton(title: "", symbol: "", action: .openURL("https://a.b")).needsConfirmation)
    }
}
