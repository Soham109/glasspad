import AppKit
import Foundation
import Testing
@testable import GlasspadMacros

/// Every built-in profile and button is valid as shipped, and starters saved by an older
/// Glasspad still load and are updated in place rather than duplicated.
@Suite struct StarterDefaultsTests {
    static func isBundleID(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil
    }

    static func isColor(_ s: String) -> Bool {
        s.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
    }

    static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    @Test func profilesHaveWellFormedUniqueBundleIDsAndOneFallback() {
        let defs = StarterLibrary.definitions
        #expect(Set(defs.map(\.key)).count == defs.count)
        #expect(Set(defs.map(\.name)).count == defs.count)
        #expect(defs.filter(\.isFallback).count == 1)
        #expect(defs.first(where: \.isFallback)?.bundleIDs.isEmpty == true)
        var seen = Set<String>()
        for p in defs where !p.isFallback {
            #expect(!p.bundleIDs.isEmpty, "\(p.name) has no app")
            #expect(Set(p.bundleIDs).count == p.bundleIDs.count, "\(p.name) lists an app twice")
            for id in p.bundleIDs {
                #expect(Self.isBundleID(id), "\(p.name): \(id)")
                #expect(seen.insert(id).inserted, "\(id) is in two starter profiles")
            }
            #expect(Self.isColor(p.color), "\(p.name): \(p.color)")
            #expect(Self.symbolExists(p.symbol), "\(p.name): no SF Symbol \(p.symbol)")
        }
    }

    @Test func everyButtonHasAUniqueTitleARealSymbolAndAKeyTheMacCanPress() {
        for p in StarterLibrary.definitions {
            #expect(!p.buttons.isEmpty, "\(p.name) is empty")
            #expect(Set(p.buttons.map(\.name)).count == p.buttons.count, "\(p.name) has two buttons with one title")
            for b in p.buttons {
                #expect(!b.name.isEmpty)
                #expect(Self.symbolExists(b.symbol), "\(p.name) \(b.name): no SF Symbol \(b.symbol)")
                #expect(b.color.map(Self.isColor) ?? true, "\(p.name) \(b.name)")
                switch b.step {
                case .keystroke(let combo):
                    #expect(combo.key.ansiKeyCode != nil, "\(p.name) \(b.name): no key code for \(combo.key)")
                    // Characters are stored unshifted and lowercase, as recording does.
                    if case .character(let c) = combo.key {
                        #expect(c.count == 1 && c == c.lowercased(), "\(p.name) \(b.name): \(c)")
                        #expect(ANSIKeyMap.charToCode[c] != nil, "\(p.name) \(b.name): \(c) is not on the keyboard unshifted")
                    }
                case .macControl(let id):
                    // Checked against the Mac's own list in GlasspadMacCore (MacControlCatalogTests).
                    #expect(!id.isEmpty, "\(p.name) \(b.name)")
                default:
                    Issue.record("\(p.name) \(b.name): a starter is one key or one Mac control, not \(b.step)")
                }
            }
        }
    }

    @Test func macrosAndProfilesLineUp() {
        let macros = StarterLibrary.macros
        let ids = Set(macros.map(\.id))
        #expect(ids.count == macros.count)
        #expect(macros.allSatisfy { $0.origin == .starter && $0.steps.count == 1 && !$0.needsScriptPermission })
        #expect(macros.allSatisfy {
            switch $0.steps.first { case .keystroke?, .macControl?: true; default: false }
        })
        let profiles = StarterLibrary.profiles
        #expect(Set(profiles.map(\.id)).count == profiles.count)
        for p in profiles {
            #expect(p.macroIDs.allSatisfy(ids.contains), "\(p.name) points at a missing macro")
            #expect(Set(p.macroIDs).count == p.macroIDs.count)
        }
        #expect(profiles.flatMap(\.macroIDs).count == macros.count)   // every starter is on a profile
        #expect(Set(profiles.map(\.id)).isDisjoint(with: ids))
    }

    /// The ids are what lets "Restore starters" and upgrades find the copies on disk. Changing
    /// the recipe would leave every user with two of each button.
    @Test func starterIDsNeverChange() {
        #expect(StarterLibrary.stableID("safari.New Tab") == UUID(uuidString: "E68C3402-77F2-5BBE-A13C-31BD87615079"))
        #expect(StarterLibrary.stableID("profile.safari") == UUID(uuidString: "218450F3-FCB2-57DE-9B90-4FA7D06D233F"))
        #expect(StarterLibrary.profiles.first { $0.name == "Safari" }?.id == StarterLibrary.stableID("profile.safari"))
    }

    @Test func roundTripsThroughTheFileFormat() throws {
        for m in StarterLibrary.macros { #expect(try MacroFile.decode(MacroFile.encode(m)) == m) }
        #expect(try ProfilesFile.decode(ProfilesFile.encode(StarterLibrary.profiles)) == StarterLibrary.profiles)
    }

    /// A starter written by an older version (another symbol, a field missing) is replaced in
    /// place by Restore, the user's own profile stays, and a hand-written version 0 file loads.
    @Test func olderStarterFilesLoadAndRestoreInPlace() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gp-qa-starters-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MacroStore(directory: dir.appendingPathComponent("macros"))
        let profiles = ProfileStore(file: dir.appendingPathComponent("profiles.json"))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)

        let newTab = StarterLibrary.stableID("safari.Reader").uuidString
        let oldStarter = #"""
        {"formatVersion":1,"macro":{"id":"\#(newTab)","name":"Reader","symbol":"plus","steps":[{"type":"keystroke","key":"r","modifiers":["shift","command"]}],"origin":"starter"}}
        """#
        try Data(oldStarter.utf8).write(to: store.directory.appendingPathComponent("\(newTab).json"))
        let mine = UUID()
        let bare = #"{"id":"\#(mine.uuidString)","name":"Mine","steps":[{"type":"wait","ms":10}]}"#
        try Data(bare.utf8).write(to: store.directory.appendingPathComponent("\(mine.uuidString).json"))
        let oldProfiles = #"""
        {"formatVersion":1,"profiles":[{"id":"\#(UUID().uuidString)","name":"My Safari","bundleIDs":["com.apple.Safari"],"macroIDs":["\#(mine.uuidString)"]}]}
        """#
        try Data(oldProfiles.utf8).write(to: profiles.file)

        let before = store.loadAll()
        #expect(before.failures.isEmpty)
        #expect(before.macros.count == 2)
        #expect(before.macros.first { $0.id.uuidString == newTab }?.symbol == "plus")
        let loaded = try #require(try profiles.load())
        #expect(loaded.first?.symbol == "square.grid.2x2" && loaded.first?.origin == .user)

        try StarterSeeder.restoreStarters(macros: store, profiles: profiles)
        let after = store.loadAll()
        #expect(after.failures.isEmpty)
        #expect(after.macros.count == StarterLibrary.macros.count + 1)
        #expect(after.macros.filter { $0.id.uuidString == newTab }.count == 1)
        #expect(after.macros.first { $0.id.uuidString == newTab }?.symbol == "doc.plaintext")
        let restored = try #require(try profiles.load())
        #expect(restored.count == StarterLibrary.profiles.count + 1)
        #expect(restored.contains { $0.name == "My Safari" })
        // A user profile beats the Safari starter.
        #expect(ProfileResolver.resolve(bundleID: "com.apple.Safari", in: restored)?.name == "My Safari")

        // Seeding a second time does nothing (a starter the user deleted stays deleted).
        #expect(try StarterSeeder.seedIfNeeded(macros: store, profiles: profiles))
        try store.delete(id: UUID(uuidString: newTab)!)
        #expect(try !StarterSeeder.seedIfNeeded(macros: store, profiles: profiles))
        #expect(store.loadAll().macros.count == StarterLibrary.macros.count)
    }

    /// The Mac's own key names stay in step with the phone's (GlasspadKit.SpecialKey), so a
    /// key a macro records is the key the phone sends.
    @Test func specialKeyCodesAreUniqueAndRoundTrip() {
        let codes = SpecialKey.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
        for k in SpecialKey.allCases { #expect(SpecialKey(keyCode: k.keyCode) == k) }
        for (ch, code) in ANSIKeyMap.charToCode {
            #expect(!codes.contains(code), "\(ch) shares a code with a named key")
            #expect(ANSIKeyMap.codeToChar[code] == ch)
        }
    }
}
