import Foundation
import Testing
@testable import GlasspadMacros

let everyStep: [MacroStep] = [
    .keystroke(KeyCombo("t", [.shift, .command])),
    .keystroke(KeyCombo(.special(.f5))),
    .keystroke(KeyCombo(.code(0x5D), [.control])),
    .typeText("Hello, \"world\" ✨\n"),
    .click(button: .right, at: .screen(100, 200), count: 2, modifiers: [.option]),
    .moveMouse(to: .window(12.5, 40, from: .topRight)),
    .drag(button: .left, from: .window(10, 10), to: .screen(500, 600), durationMs: 450),
    .scroll(dx: -3, dy: 120),
    .wait(ms: 250),
    .waitForApp(bundleID: "com.apple.Safari", timeoutMs: 4000),
    .openApp(bundleID: "com.apple.Music"),
    .openURL("https://example.com/a?b=c"),
    .openFile(path: "~/Desktop/notes.txt"),
    .runShortcut(nameOrID: "Make GIF", input: "some input"),
    .runShortcut(nameOrID: "8CDF5F7A-6BA1-47E9-BA61-7DF47DE0B4F6", input: nil),
    .runAppleScript(source: "tell application \"Finder\" to activate"),
    .runShell(command: "echo hi | tr a-z A-Z", timeoutMs: 1000),
    .setClipboard("copied"),
    .notify(title: "Done", body: "All good"),
    .repeatBlock(count: 3, steps: [
        .keystroke(KeyCombo(.special(.down))),
        .repeatBlock(count: 2, steps: [.typeText("x"), .wait(ms: 10)]),
    ]),
]

@Suite("Macro model and storage")
struct ModelTests {
    @Test func everyStepTypeRoundTrips() throws {
        let macro = Macro(name: "All", symbol: "star.fill", color: "#FF9F0A", steps: everyStep, allowScripts: true,
                          gestureTriggers: ["fourFingerTap"], hotkey: KeyCombo("m", [.control, .option]),
                          origin: .recorded)
        let data = try MacroFile.encode(macro)
        let back = try MacroFile.decode(data)
        #expect(back == macro)
        // Every step type in the enum is covered by this fixture.
        var types = Set<String>()
        func collect(_ s: [MacroStep]) {
            for step in s {
                types.insert(step.typeName)
                if case .repeatBlock(_, let inner) = step { collect(inner) }
            }
        }
        collect(everyStep)
        #expect(types.count == 17)
    }

    @Test func jsonIsReadableAndVersioned() throws {
        let macro = Macro(name: "Tab", steps: [.keystroke(KeyCombo("t", [.command, .shift]))])
        let json = String(decoding: try MacroFile.encode(macro), as: UTF8.self)
        #expect(json.contains("\"formatVersion\" : 1"))
        #expect(json.contains("\"type\" : \"keystroke\""))
        #expect(json.contains("\"key\" : \"t\""))
        // Modifiers are written in menu order regardless of how they were built.
        #expect(json.contains("\"shift\",\n"))
        #expect(json.contains("\"command\""))
    }

    @Test func newerFormatVersionIsRefused() throws {
        let json = #"{"formatVersion": 2, "macro": {"id": "\#(UUID().uuidString)", "name": "x", "steps": []}}"#
        #expect(throws: MacroError.unsupportedFormatVersion(found: 2, supported: 1)) {
            try MacroFile.decode(Data(json.utf8))
        }
    }

    @Test func versionZeroBareMacroWithDefaultsIsRead() throws {
        let id = UUID()
        let json = #"""
        {"id": "\#(id.uuidString)", "name": "Hand written",
         "steps": [{"type": "keystroke", "key": "return"},
                   {"type": "click", "at": {"x": 5, "y": 6}},
                   {"type": "wait", "ms": 100}]}
        """#
        let m = try MacroFile.decode(Data(json.utf8))
        #expect(m.id == id)
        #expect(m.symbol == "bolt.fill")
        #expect(m.allowScripts == false)
        #expect(m.origin == .user)
        #expect(m.steps == [.keystroke(KeyCombo(.special(.returnKey))),
                            .click(button: .left, at: .screen(5, 6), count: 1, modifiers: []),
                            .wait(ms: 100)])
    }

    @Test func unknownStepTypeAndKeyAreErrors() {
        let badType = #"{"formatVersion":1,"macro":{"id":"\#(UUID().uuidString)","name":"x","steps":[{"type":"teleport"}]}}"#
        #expect(throws: DecodingError.self) { try MacroFile.decode(Data(badType.utf8)) }
        let badKey = #"{"formatVersion":1,"macro":{"id":"\#(UUID().uuidString)","name":"x","steps":[{"type":"keystroke","key":"banana"}]}}"#
        #expect(throws: DecodingError.self) { try MacroFile.decode(Data(badKey.utf8)) }
        let badMod = #"{"formatVersion":1,"macro":{"id":"\#(UUID().uuidString)","name":"x","steps":[{"type":"keystroke","key":"a","modifiers":["hyper"]}]}}"#
        #expect(throws: DecodingError.self) { try MacroFile.decode(Data(badMod.utf8)) }
    }

    @Test func keyNames() {
        #expect(MacroKey(jsonName: "A") == .character("a"))
        #expect(MacroKey(jsonName: " ") == .special(.space))
        #expect(MacroKey(jsonName: "pageDown") == .special(.pageDown))
        #expect(MacroKey(jsonName: "code:93") == .code(93))
        #expect(MacroKey(jsonName: "nope") == nil)
        #expect(KeyCombo("t", [.command, .shift, .control, .option]).displayString == "⌃⌥⇧⌘T")
        #expect(MacroKey.character("t").ansiKeyCode == 0x11)
        #expect(MacroKey.special(.returnKey).ansiKeyCode == 0x24)
    }

    @Test func storeSavesLoadsDeletesAndSurvivesABrokenFile() throws {
        let dir = tempDir()
        let store = MacroStore(directory: dir.appendingPathComponent("macros"))
        let a = Macro(name: "A", steps: [.wait(ms: 1)])
        let b = Macro(name: "B", steps: everyStep, allowScripts: true)
        try store.save(a)
        try store.save(b)
        try Data("{ not json".utf8).write(to: store.directory.appendingPathComponent("broken.json"))
        let future = #"{"formatVersion": 9, "macro": {}}"#
        try Data(future.utf8).write(to: store.directory.appendingPathComponent("future.json"))

        let loaded = store.loadAll()
        #expect(Set(loaded.macros) == Set([a, b]))
        #expect(loaded.failures.map(\.file).sorted() == ["broken.json", "future.json"])
        #expect(loaded.failures.first { $0.file == "future.json" }!.message.contains("version 9"))

        #expect(try store.load(id: a.id) == a)
        try store.delete(id: a.id)
        #expect(throws: MacroError.macroNotFound(a.id)) { try store.load(id: a.id) }
        #expect(store.loadAll().macros == [b])
    }

    @Test func defaultDirectoryIsApplicationSupport() {
        #expect(MacroStore.defaultDirectory.path.hasSuffix("Library/Application Support/Glasspad/macros"))
        #expect(ProfileStore.defaultFile.path.hasSuffix("Library/Application Support/Glasspad/profiles.json"))
    }

    @Test func scriptPermissionIsDetectedInsideRepeats() {
        #expect(!Macro(name: "x", steps: [.typeText("a")]).needsScriptPermission)
        #expect(Macro(name: "x", steps: [.repeatBlock(count: 2, steps: [.repeatBlock(count: 2, steps: [
            .runAppleScript(source: "beep")])])]).needsScriptPermission)
    }

    @Test func profilesFileRoundTripsAndIsVersioned() throws {
        let p = ContextProfile(name: "Mine", bundleIDs: ["com.x"], macroIDs: [UUID(), UUID()])
        #expect(try ProfilesFile.decode(ProfilesFile.encode([p])) == [p])
        #expect(throws: MacroError.unsupportedFormatVersion(found: 3, supported: 1)) {
            try ProfilesFile.decode(Data(#"{"formatVersion":3,"profiles":[]}"#.utf8))
        }
    }
}
