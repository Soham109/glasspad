import CoreGraphics
import Foundation
import Testing
@testable import GlasspadKit

/// A phone and a Mac built at different times keep working: every message survives the wire,
/// data saved by older builds loads, and what this build cannot read is dropped on its own.
@Suite struct CompatibilityTests {
    static let id = UUID(uuidString: "0E3C9A1B-4D2F-4A55-9C21-7F8A6B3C9D11")!

    /// One of every DeckAction, with every Mac control.
    static var everyAction: [DeckAction] {
        [.openApp(bundleID: "com.apple.Notes"), .openURL("https://www.apple.com"), .runShortcut(name: "Focus"),
         .keystroke(Keystroke(key: .special(.f5), modifiers: [.function])), .shellScript("echo hi"),
         .openFile(path: "~/Downloads"), .runMacro(id: id), .typeText("héllo"),
         .screenshot(DeckScreenshot(area: .selection, sendToPhone: .clipboard, copyToMacClipboard: true)),
         .screenRecording, .setAudioOutput(name: "AirPods Pro"), .folder,
         .unsupported(UnsupportedDeckAction(raw: .object(["hologram": .object(["depth": .number(3), "on": .bool(true)])])))]
            + DeckSystemAction.allCases.map(DeckAction.system)
    }

    static var everyMessage: [ModeMessage] {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 9])
        let app = DockApp(bundleID: "com.apple.Safari", name: "Safari", iconPNG: png, running: true, active: true,
                          iconKey: "com.apple.Safari@1", inDock: true, recent: false, hidden: false)
        let buttons = everyAction.enumerated().map { i, a in
            DeckButton(title: "B\(i)", symbol: "star", action: a, color: "#0A84FF", size: i == 0 ? .wide : nil,
                       children: a == .folder ? [DeckButton(title: "In", symbol: "star", action: .typeText("x"))] : nil)
        }
        let layout = DeckLayout(pages: [DeckPage(title: "P", symbol: "pin", appBundleIDs: ["com.apple.Safari"], buttons: buttons)],
                                columns: 4, allowsShellCommands: false)
        let state = MacDockState(hidden: true, hideWhileConnected: false, isHiddenNow: true)
        var all: [ModeMessage] = GlasspadMode.allCases.map(ModeMessage.modeSelected)
        all += [.modesShown([.present, .dock, .remote]), .modesShown([])]
        all += [.dockRequest, .dockList(apps: [app]), .dockOpen(bundleID: "com.apple.Notes"), .dockSync(iconKeys: ["k"]),
                .dockOpenResult(bundleID: "x", ok: false, message: "Not running: x"), .dockCatalogRequest,
                .dockCatalog(apps: [app]), .dockIconRequest(bundleIDs: ["a.b"]), .dockIcons(apps: [app]),
                .frontmostApp(bundleID: nil), .frontmostApp(bundleID: "com.apple.TV"), .macDockState(state), .macDockSet(state)]
        all += DockAppAction.allCases.map { .dockAppAction(bundleID: "com.apple.Safari", action: $0) }
        all += [.keysText("héllo 👋\n")]
        all += SpecialKey.allCases.map { .keysKeystroke(Keystroke(key: .special($0), modifiers: [.command, .shift, .option, .control, .function])) }
        all += [.mediaRequest, .mediaState(MediaState(title: "Song", isPlaying: true, duration: 200, elapsed: 3, volume: 0.5,
                                                      playbackRate: 1, sourceBundleID: "com.spotify.client", shuffle: true,
                                                      repeatMode: .one, canSeek: true)),
                .mediaSetVolume(0.25), .mediaSetBrightness(1), .mediaControl(.seek(42)), .mediaControl(.setShuffle(false)),
                .mediaControl(.selectOutput(id: "BuiltIn"))]
        all += MediaCommand.allCases.map(ModeMessage.mediaCommand)
        all += MediaRepeatMode.allCases.map { .mediaControl(.setRepeat($0)) }
        all += [.deckRequest, .deckButtons(buttons), .deckRun(id: id), .deckResult(id: id, ok: true, message: "Night Shift is on"),
                .deckLayout(layout), .deckSave(layout), .deckSaveResult(ok: false, message: "x"), .deckRunConfirmed(id: id),
                .deckCatalogRequest, .deckCatalog(DeckCatalog(audioOutputs: ["A"], shortcuts: ["S"]))]
        all += DeckImageDestination.allCases.map { .deckImage(id: id, imageData: png, destination: $0) }
        all += [.clipboardPush(.text("t")), .clipboardPush(.imagePNG(png)), .clipboardPull, .clipboardContent(nil),
                .clipboardContent(.imagePNG(png)), .clipboardPushResult(ok: true, message: nil),
                .clipboardPullRefused(message: "too big")]
        all += [.presentNext, .presentPrevious, .presentLaser(on: false), .presentLaserPosition(x: 0, y: 1)]
        all += DeckSystemAction.allCases.map { .remoteSystem(id: id, action: $0) }
        let shown = DisplaysState(displays: [], windows: [], nightShift: true, canArrangeWindows: false, tileMargin: 4,
                                  pending: PendingDisplayChange(summary: "Studio Display looks like 2560 by 1440", secondsLeft: 12))
        all += [.displaysWatch(on: true), .displaysWatch(on: false), .displaysState(shown),
                .displaysResult(id: id, ok: false, message: "That display is not connected any more.")]
        all += ([.raise, .split(with: 7), .move(display: 2, origin: nil), .move(display: 2, origin: CGPoint(x: 1, y: 2)),
                 .minimize, .close, .fullScreen] + WindowTile.allCases.map(WindowCommand.tile))
            .map { .windowCommand(id: id, windowID: 42, command: $0) }
        all += [DisplayCommand.brightness(display: 1, value: 0.5), .resolution(display: 1, id: 3), .mirror(display: 2, of: 1),
                .mirror(display: 2, of: nil), .makeMain(display: 2), .arrange([DisplayOrigin(display: 1, origin: .zero)]),
                .keepChanges, .revertChanges].map { .displayCommand(id: id, command: $0) }
        all += ControlMessageTests.everyMacroMessage.map(ModeMessage.macro)
        return all
    }

    /// Fails to compile when a case is added, so this suite has to learn about it.
    static func covered(_ m: ModeMessage) -> String {
        switch m {
        case .modeSelected, .modesShown, .dockRequest, .dockList, .dockOpen, .dockSync, .dockAppAction, .dockOpenResult,
             .dockCatalogRequest, .dockCatalog, .dockIconRequest, .dockIcons, .frontmostApp, .macDockState, .macDockSet,
             .keysText, .keysKeystroke, .mediaRequest, .mediaState, .mediaCommand, .mediaSetVolume, .mediaSetBrightness,
             .mediaControl, .deckRequest, .deckButtons, .deckRun, .deckResult, .deckLayout, .deckSave, .deckSaveResult,
             .deckRunConfirmed, .deckCatalogRequest, .deckCatalog, .deckImage, .clipboardPush, .clipboardPull,
             .clipboardContent, .clipboardPushResult, .clipboardPullRefused, .presentNext, .presentPrevious, .presentLaser,
             .presentLaserPosition, .remoteSystem, .displaysWatch, .displaysState, .windowCommand, .displayCommand,
             .displaysResult, .macro:
            m.tag
        }
    }

    @Test func everyMessageAndPayloadRoundTripsOnTheWire() throws {
        let all = Self.everyMessage
        #expect(Set(all.map(Self.covered)).count == 50)      // every case at least once
        for m in all {
            let data = try ControlMessage.mode(m).jsonData()
            #expect(try ControlMessage.from(jsonData: data) == .mode(m), "\(m.tag)")
            #expect(data.count < GlasspadService.maxFrameLength)
        }
    }

    // MARK: Saved data from older builds

    /// A Deck cached on the phone (or sent by a Mac) before pages, sizes, folders, colours and
    /// screenshot options existed, in the older synthesized action shape.
    @Test func aDeckSavedBeforeTheNewFieldsLoads() throws {
        let json = #"""
        {"pages":[{"id":"\#(Self.id.uuidString)","title":"Main","buttons":[
          {"id":"\#(UUID().uuidString)","title":"Safari","symbol":"safari","action":{"openApp":{"bundleID":"com.apple.Safari"}}},
          {"id":"\#(UUID().uuidString)","title":"Copy","symbol":"doc.on.doc","action":{"keystroke":{"_0":{"key":{"character":{"_0":"c"}},"modifiers":1}}}},
          {"id":"\#(UUID().uuidString)","title":"Shot","symbol":"camera","action":{"screenshot":{"_0":{"area":"fullScreen"}}}},
          {"id":"\#(UUID().uuidString)","title":"Lock","symbol":"lock","action":{"system":{"_0":"lockScreen"}}}
        ]}]}
        """#
        let layout = try JSONDecoder().decode(DeckLayout.self, from: Data(json.utf8))
        #expect(layout.columns == nil && layout.allowsShellCommands == nil)
        #expect(layout.pages.first?.symbol == nil && layout.pages.first?.appBundleIDs == nil)
        let b = layout.allButtons
        #expect(b.map(\.action) == [.openApp(bundleID: "com.apple.Safari"),
                                    .keystroke(Keystroke(key: .character("c"), modifiers: .command)),
                                    .screenshot(DeckScreenshot(area: .fullScreen)), .system(.lockScreen)])
        #expect(b.allSatisfy { $0.color == nil && $0.size == nil && $0.children == nil })
        // And the one-screen Actions shape is made from it without losing a button.
        let migrated = PinnedDeck.migrated(layout, macros: [])
        #expect(PinnedDeck.pinned(in: migrated).map(\.title) == ["Safari", "Copy", "Shot", "Lock"])
        #expect(PinnedDeck.migrated(migrated, macros: []) == migrated)
    }

    /// A mode list saved before Remote existed keeps the user's choices and adds Remote hidden.
    @Test func aModeListSavedBeforeRemoteLoads() throws {
        let old = #"{"order":["trackpad","media","keys","dock","actions","deck","macros","clipboard","present"],"hidden":["media"],"splitActions":false}"#
        let list = try JSONDecoder().decode(ModeListLayout.self, from: Data(old.utf8))
        // Every mode added since starts hidden, after the saved ones.
        #expect(list.order.prefix(9) == ["trackpad", "media", "keys", "dock", "actions", "deck", "macros", "clipboard", "present"])
        #expect(Set(list.order.dropFirst(9)) == ModeListLayout.hiddenAtFirst)
        #expect(list.hidden == Set(["media"]).union(ModeListLayout.hiddenAtFirst))
        #expect(list.visible(known: ModeListLayout.defaultOrder) == ["trackpad", "keys", "dock", "actions"])
        // Saving and loading again changes nothing; a Remote the user turned on stays on.
        var shown = list
        shown.hidden.remove("remote")
        let again = try JSONDecoder().decode(ModeListLayout.self, from: JSONEncoder().encode(shown))
        #expect(again == shown)
        #expect(again.visible(known: ModeListLayout.defaultOrder).contains("remote"))
        // A list from before Actions (no "actions" in it) still shows every known mode once.
        let older = #"{"order":["trackpad","keys","media","dock","deck","macros","clipboard","present"],"hidden":[],"splitActions":true}"#
        let split = try JSONDecoder().decode(ModeListLayout.self, from: Data(older.utf8))
        let visible = split.visible(known: ModeListLayout.defaultOrder)
        #expect(Set(visible).count == visible.count)
        #expect(visible.contains("deck") && !visible.contains("actions") && !visible.contains("remote"))
    }

    // MARK: What an older build does with this build's new messages

    /// Each addition is under a tag or value an older build does not know, so it throws and the
    /// transport drops that one message (see PhoneSessionTests) instead of reading it as
    /// something else.
    @Test func newMessagesUseTagsAnOlderBuildDrops() throws {
        func json(_ m: ModeMessage) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(m)) as! [String: Any]
        }
        #expect(try json(.modeSelected(.remote)) as NSDictionary == ["t": "modeSelected", "mode": "remote"])
        let remote = try json(.remoteSystem(id: Self.id, action: .keepAwake))
        #expect(remote as NSDictionary == ["t": "remoteSystem", "id": Self.id.uuidString, "action": "keepAwake"])
        let f5 = try json(.keysKeystroke(Keystroke(key: .special(.f5))))
        #expect(((f5["keystroke"] as? [String: Any])?["key"] as? [String: Any]).map { $0 as NSDictionary }
                == ["special": ["_0": "f5"]] as NSDictionary)
    }

    /// What this build does with a newer build's additions: an unknown screen, Mac control or
    /// key is not misread as another one.
    @Test func unknownValuesFromANewerBuildAreNotMisread() throws {
        let unknown = [
            #"{"t":"modeSelected","mode":"hologram"}"#,
            #"{"t":"remoteSystem","id":"\#(Self.id.uuidString)","action":"teleport"}"#,
            #"{"t":"keysKeystroke","keystroke":{"key":{"special":{"_0":"f19"}},"modifiers":0}}"#,
            #"{"t":"mediaCommand","command":"rewind"}"#,
        ]
        for j in unknown {
            #expect(throws: (any Error).self, "\(j)") { try JSONDecoder().decode(ModeMessage.self, from: Data(j.utf8)) }
        }
        // A screen a newer phone names beside the others is skipped, not the whole list.
        let panes = #"{"t":"modesShown","modes":["present","hologram","dock"]}"#
        #expect(try JSONDecoder().decode(ModeMessage.self, from: Data(panes.utf8)) == .modesShown([.present, .dock]))
        // Older fields stay readable when a newer build adds more beside them.
        let extra = #"{"t":"deckResult","id":"\#(Self.id.uuidString)","ok":true,"message":null,"undo":true}"#
        #expect(try JSONDecoder().decode(ModeMessage.self, from: Data(extra.utf8)) == .deckResult(id: Self.id, ok: true, message: nil))
        let media = #"{"t":"mediaState","state":{"isPlaying":true,"title":"Song","lyrics":"la la","repeatMode":"shuffleForever"}}"#
        let decoded = try? JSONDecoder().decode(ModeMessage.self, from: Data(media.utf8))
        guard case .mediaState(let s)? = decoded else { Issue.record("media state with extras dropped"); return }
        #expect(s.title == "Song" && s.repeatMode == .off)
    }

    /// A Mac control added later (one this build does not know) inside a Deck layout costs only
    /// that button: it reads as `.unsupported`, every other button stays, and saving the layout
    /// writes the newer button back exactly as it came.
    @Test func oneUnknownMacControlKeepsTheWholeDeck() throws {
        let known = DeckButton(id: Self.id, title: "Lock", symbol: "lock.fill", action: .system(.lockScreen))
        let newer = DeckButton(id: UUID(), title: "Future", symbol: "sparkles", action: .system(.lockScreen))
        var json = String(decoding: try JSONEncoder().encode(ModeMessage.deckLayout(
            DeckLayout(pages: [DeckPage(title: "P", buttons: [known, newer])]))), as: UTF8.self)
        // The second button becomes one from a newer Mac.
        let range = try #require(json.range(of: "lockScreen", options: .backwards))
        json.replaceSubrange(range, with: "futureControl")
        let m = try JSONDecoder().decode(ModeMessage.self, from: Data(json.utf8))
        guard case .deckLayout(let l) = m else { Issue.record("not a layout"); return }
        #expect(l.allButtons.map(\.title) == ["Lock", "Future"])
        #expect(l.allButtons[0].action == .system(.lockScreen))
        #expect(!l.allButtons[1].action.isSupported)
        #expect(!l.allButtons[1].needsConfirmation)
        // Written back by this build, the newer button is unchanged.
        let again = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ModeMessage.deckSave(l))) as! [String: Any]
        let original = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        #expect((again["layout"] as? NSDictionary) == (original["layout"] as? NSDictionary))
    }

    /// A whole new kind of action, one with newer fields, and a size added later all keep their
    /// button; only what cannot be read at all (no id, a page without a title) is skipped.
    @Test func newerDeckButtonsAndPagesKeepTheRestReadable() throws {
        let id = Self.id.uuidString
        let json = #"""
        {"t":"deckLayout","layout":{"columns":4,"pages":[
          {"id":"\#(id)","title":"Main","buttons":[
            {"id":"\#(id)","title":"Hologram","symbol":"cube","action":{"hologram":{"depth":3,"tags":["a",true,null]}}},
            {"id":"\#(id)","title":"Big","symbol":"star","size":"huge","action":{"openURL":{"_0":"https://apple.com"}}},
            {"title":"Broken","symbol":"xmark","action":{"folder":{}}},
            {"id":"\#(id)","title":"Folder","symbol":"folder","action":{"folder":{}},"children":[
              {"id":"\#(id)","title":"Inner","symbol":"bolt","action":{"system":{"_0":"warpDrive"}}},
              {"id":"\#(id)","title":"Lost"}
            ]}
          ]},
          {"id":"\#(id)","buttons":[]}
        ]}}
        """#
        guard case .deckLayout(let l) = try JSONDecoder().decode(ModeMessage.self, from: Data(json.utf8)) else {
            Issue.record("not a layout"); return
        }
        #expect(l.pages.count == 1 && l.columns == 4)
        #expect(l.allButtons.map(\.title) == ["Hologram", "Big", "Folder", "Inner"])
        #expect(l.allButtons.map(\.action.isSupported) == [false, true, true, false])
        #expect(l.allButtons[1].size == nil && l.allButtons[1].action == .openURL("https://apple.com"))
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(l.allButtons[0].action)) as! NSDictionary
        #expect(raw == ["hologram": ["depth": 3, "tags": ["a", true, NSNull()]]] as NSDictionary)
        // The flat list an older phone reads skips only the unreadable button too.
        let flat = #"{"t":"deckButtons","buttons":[{"id":"\#(id)","title":"A","symbol":"a","action":{"hologram":{}}},{"title":"B"}]}"#
        guard case .deckButtons(let b) = try JSONDecoder().decode(ModeMessage.self, from: Data(flat.utf8)) else {
            Issue.record("not buttons"); return
        }
        #expect(b.map(\.title) == ["A"])
    }
}
