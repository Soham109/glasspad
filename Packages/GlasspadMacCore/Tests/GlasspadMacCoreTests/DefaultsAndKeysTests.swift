import AppKit
import Foundation
import GlasspadMacros
import Testing
@testable import GlasspadKit
@testable import GlasspadMacCore

private func symbolExists(_ name: String) -> Bool {
    NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
}

private func isColor(_ s: String?) -> Bool {
    guard let s else { return true }
    return s.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
}

private let dashes = CharacterSet(charactersIn: "\u{2013}\u{2014}")

/// Every button Glasspad ships with is one the Mac runs, with a real symbol and a valid colour.
@Suite @MainActor struct ShippedButtonsTests {
    static let lists: [(String, [DeckButton])] = [
        ("Pinned essentials", PinnedDeck.essentials()),
        ("Mac page", DeckConfig.macStarterButtons()),
        ("Version 2 starters", DeckConfig.starterButtons),
        ("My Buttons starters", DeckConfig.myStarterButtons),
        ("New Deck", DeckConfig.starterPages().flatMap(\.buttons)),
    ]

    @Test func everyShippedButtonLooksRight() {
        for (name, buttons) in Self.lists {
            #expect(!buttons.isEmpty, "\(name)")
            #expect(Set(buttons.map(\.title)).count == buttons.count, "\(name) has two buttons with one title")
            #expect(Set(buttons.map(\.id)).count == buttons.count, "\(name) reuses an id")
            for b in buttons {
                #expect(!b.title.isEmpty)
                #expect(b.title.rangeOfCharacter(from: dashes) == nil, "\(name): \(b.title)")
                #expect(symbolExists(b.symbol), "\(name) \(b.title): no SF Symbol \(b.symbol)")
                #expect(isColor(b.color), "\(name) \(b.title): \(b.color ?? "")")
                #expect(b.action != .folder)
            }
        }
        // Fresh ids each time, so a reset never collides with buttons already on the Deck.
        #expect(Set(PinnedDeck.essentials().map(\.id)).isDisjoint(with: PinnedDeck.essentials().map(\.id)))
    }

    /// Run on a pretend Mac: every shipped button succeeds, and none needs a shortcut the user
    /// would have to make first.
    @Test func everyShippedButtonRunsOnTheMac() async {
        let env = FakeDeckEnvironment()
        env.existing.insert("/Users/test/Downloads")
        let deck = DeckMode(env: env, url: tempURL("deck.json"))
        for (name, buttons) in Self.lists {
            for b in buttons {
                let outcome = await deck.perform(b.action)
                #expect(outcome.ok, "\(name) \(b.title): \(outcome.message ?? "")")
                #expect(outcome.message != "Not built yet", "\(name) \(b.title)")
            }
        }
        #expect(!env.runs.contains { $0.0 == "/usr/bin/shortcuts" }, "a shipped button runs a shortcut the user may not have")
    }

    /// The new Deck file written for a first launch holds exactly the essentials, and loads back.
    @Test func aNewDeckFileLoadsBack() throws {
        let url = tempURL("deck.json")
        let deck = DeckMode(env: FakeDeckEnvironment(), url: url)
        let again = DeckConfig.load(from: url)
        #expect(again == deck.config)
        #expect(again.layout.pages.map(\.id) == [PinnedDeck.pinnedPageID])
        #expect(again.layout.allButtons.map(\.title) == PinnedDeck.essentials().map(\.title))
        #expect(again.allowShellCommands == false)
    }
}

/// The phone's Library lists every Mac control from DeckSystemCatalog.
@Suite struct MacControlCatalogTests {
    @Test func everyControlHasATitleSymbolColourAndGroup() {
        let all = DeckSystemAction.allCases
        #expect(Set(all.map(\.title)).count == all.count)
        for a in all {
            #expect(!a.title.isEmpty)
            #expect(a.title.rangeOfCharacter(from: dashes) == nil && a.detail.rangeOfCharacter(from: dashes) == nil, "\(a)")
            #expect(symbolExists(a.symbol), "\(a): no SF Symbol \(a.symbol)")
            #expect(isColor(a.color), "\(a)")
        }
        for g in DeckSystemGroup.allCases { #expect(all.contains { $0.group == g }, "\(g) is empty") }
        // The ones that ask first say so in the Library.
        for a in all where a.needsConfirmation { #expect(a.detail == "Asks first", "\(a)") }
        #expect(all.filter(\.needsConfirmation) == [.sleepMac, .emptyTrash])
    }

    /// SF Symbols named in the iPhone app's source, checked here because only the Mac test run
    /// can ask for them by name. A typo shows as an empty tile.
    @Test func everySymbolNamedInTheAppsExists() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let pattern = try NSRegularExpression(pattern: #"(?:systemName|systemImage|symbol): *"([a-z0-9][a-z0-9.]*)""#)
        var checked = 0
        for dir in ["Apps/iOS/Sources", "Apps/iOS/Widgets", "Apps/iOS/Shared", "Apps/Mac/Sources"] {
            let base = root.appendingPathComponent(dir)
            guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for m in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let r = Range(m.range(at: 1), in: text) else { continue }
                    let name = String(text[r])
                    checked += 1
                    #expect(symbolExists(name), "\(file.lastPathComponent): no SF Symbol \(name)")
                }
            }
        }
        #expect(checked > 50)
    }
}

/// Every key the phone can send becomes a real key on the Mac.
@Suite @MainActor struct PhoneKeysReachTheMacTests {
    static let players: [RemotePlayer] = RemoteSite.allCases.map(RemotePlayer.browser)
        + [.appleTV, .quickTime, .iina, .vlc, .infuse, .music, .other]

    func pressable(_ k: Keystroke) -> Bool { KeysMode.keyStroke(for: k) != nil }

    @Test func everyNamedKeyHasItsOwnCode() {
        let codes = GlasspadKit.SpecialKey.allCases.map { KeysMode.keyStroke(for: Keystroke(key: .special($0)))?.keyCode }
        #expect(codes.allSatisfy { $0 != nil })
        #expect(Set(codes).count == codes.count)
        // The F-keys carry the fn flag, as on a real keyboard.
        let fKeys: [GlasspadKit.SpecialKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
        #expect(Set(fKeys.compactMap { KeysMode.specialCodes[$0] }) == KeyboardSynth.functionKeyCodes)
        // The same names as macros use, with the same codes.
        for k in GlasspadKit.SpecialKey.allCases {
            let name = k == .returnKey ? "return" : k.rawValue
            let macroKey = GlasspadMacros.SpecialKey(rawValue: name)
            #expect(macroKey?.keyCode == KeysMode.specialCodes[k], "\(k)")
        }
    }

    /// With a modifier armed, any character typed on the iPhone keyboard is sent as a key.
    @Test func everyCharacterOnAUSKeyboardIsAKeyWithAndWithoutModifiers() {
        let printable = (32...126).map { String(UnicodeScalar(UInt8($0))) }
        for ch in printable {
            for mods: GlasspadKit.KeyModifiers in [[], [.command], [.shift], [.control], [.option], [.command, .shift, .option, .control]] {
                let k = Keystroke(key: .character(ch), modifiers: mods)
                let stroke = KeysMode.keyStroke(for: k)
                #expect(stroke != nil, "\(ch) \(mods)")
                #expect(stroke?.command == mods.contains(.command) && stroke?.option == mods.contains(.option)
                        && stroke?.control == mods.contains(.control))
            }
        }
        // Capitals and shifted symbols press Shift.
        #expect(KeysMode.keyStroke(for: Keystroke(key: .character("A")))?.shift == true)
        #expect(KeysMode.keyStroke(for: Keystroke(key: .character("?")))?.keyCode == 44)
        #expect(KeysMode.keyStroke(for: Keystroke(key: .character("?")))?.shift == true)
        // Not a single key: typed as text by KeysMode.press instead.
        #expect(KeysMode.keyStroke(for: Keystroke(key: .character("ab"))) == nil)
        #expect(KeysMode.keyStroke(for: Keystroke(key: .character("é"))) == nil)
    }

    @Test func everyRemoteButtonIsAKeyOrAMediaCommand() {
        for player in Self.players {
            let map = RemoteKeymap(player: player)
            #expect(map.has(.playPause), "\(player)")
            for action in RemoteAction.allCases {
                guard let out = map.output(action) else { continue }
                for (position, canSeek) in [(Double?.some(30), true), (nil, false)] {
                    let messages = RemoteKeymap.message(for: out, position: position, canSeek: canSeek, duration: 100)
                    for m in messages {
                        switch m {
                        case .keysKeystroke(let k): #expect(pressable(k), "\(player) \(action): \(k)")
                        case .mediaCommand, .mediaControl: break
                        default: Issue.record("\(player) \(action) sends \(m)")
                        }
                    }
                }
            }
            for k in map.searchPrefix { #expect(pressable(k), "\(player) search: \(k)") }
        }
        // Search ends with Return, and the Control Center shortcut is ctrl+up.
        #expect(pressable(Keystroke(key: .special(.returnKey))))
        #expect(KeysMode.keyStroke(for: Keystroke(key: .special(.up), modifiers: .control))?.control == true)
    }

    /// The Keys screen's shortcut row and the starter keystroke buttons.
    @Test func shortcutRowAndShippedKeystrokesArePressable() {
        for ch in ["c", "v", "x", "z", "a", "f", "s", "t", "w"] {
            #expect(pressable(Keystroke(key: .character(ch), modifiers: .command)), "\(ch)")
        }
        let shipped = ShippedButtonsTests.lists.flatMap(\.1).compactMap { b -> Keystroke? in
            if case .keystroke(let k) = b.action { return k } else { return nil }
        }
        for k in shipped { #expect(pressable(k), "\(k)") }
        // Lock Screen's fallback chord.
        let lock = KeysMode.keyStroke(for: Keystroke(key: .character("q"), modifiers: [.command, .control]))
        #expect(lock?.keyCode == 12 && lock?.command == true && lock?.control == true)
    }

    @Test func keyCodeNamesMatchTheANSITable() {
        let named: [(KeyCode, Character)] = [(.a, "a"), (.s, "s"), (.d, "d"), (.f, "f"), (.h, "h"), (.g, "g"), (.z, "z"),
                                             (.x, "x"), (.c, "c"), (.v, "v"), (.b, "b"), (.q, "q"), (.w, "w"), (.e, "e"),
                                             (.r, "r"), (.y, "y"), (.t, "t"), (.o, "o"), (.u, "u"), (.i, "i"), (.p, "p"),
                                             (.l, "l"), (.j, "j"), (.k, "k"), (.n, "n"), (.m, "m"),
                                             (.rightBracket, "]"), (.leftBracket, "[")]
        for (code, ch) in named { #expect(KeysMode.ansiCodes[ch] == code.rawValue, "\(ch)") }
        for (ch, code) in KeysMode.shiftedANSI {
            #expect(KeyLayout.ansi.key(for: ch, shortcut: false).map { $0.code == code && $0.shift } == true, "\(ch)")
        }
    }
}
