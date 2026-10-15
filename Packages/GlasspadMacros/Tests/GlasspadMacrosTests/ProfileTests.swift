import Foundation
import Testing
@testable import GlasspadMacros

@Suite("Context profiles")
struct ProfileTests {
    let fallback = ContextProfile(name: "Everywhere", bundleIDs: [], macroIDs: [], isFallback: true, origin: .starter)
    let safariStarter = ContextProfile(name: "Safari", bundleIDs: ["com.apple.Safari"], macroIDs: [], origin: .starter)
    let browsers = ContextProfile(name: "My Browsers", bundleIDs: ["com.apple.Safari", "com.google.Chrome"], macroIDs: [])

    @Test func resolverPrefersUserProfilesThenStartersThenFallback() {
        let all = [fallback, safariStarter, browsers]
        #expect(ProfileResolver.resolve(bundleID: "com.apple.Safari", in: all) == browsers)
        #expect(ProfileResolver.resolve(bundleID: "com.apple.Safari", in: [fallback, safariStarter]) == safariStarter)
        #expect(ProfileResolver.resolve(bundleID: "com.google.Chrome", in: all) == browsers)
        #expect(ProfileResolver.resolve(bundleID: "com.unknown", in: all) == fallback)
        #expect(ProfileResolver.resolve(bundleID: nil, in: all) == fallback)
        #expect(ProfileResolver.resolve(bundleID: "com.unknown", in: [safariStarter]) == nil)
    }

    @Test func switcherPublishesOnlyRealChangesAndIgnoresGlasspad() {
        let observer = FakeFrontmostObserver(current: "com.apple.finder")
        let switcher = ProfileSwitcher(observer: observer, profiles: [fallback, safariStarter, browsers],
                                       ignoredBundleIDs: ["app.glasspad.mac"])
        let seen = LockedBox<[String?]>([])
        switcher.start { p in seen.update { $0.append(p?.name) } }
        observer.activate("com.apple.Safari")
        observer.activate("com.google.Chrome")      // same profile: no event
        observer.activate("app.glasspad.mac")       // our own menu: ignored
        observer.activate("com.apple.TextEdit")
        observer.activate("com.apple.Notes")        // still the fallback: no event
        #expect(seen.get() == ["Everywhere", "My Browsers", "Everywhere"])
        #expect(switcher.frontmostBundleID == "com.apple.Notes")

        // Editing the profile list re-resolves immediately.
        switcher.update(profiles: [fallback, ContextProfile(name: "Notes", bundleIDs: ["com.apple.Notes"], macroIDs: [])])
        #expect(seen.get().last == "Notes")
        switcher.stop()
        observer.activate("com.apple.Safari")
        #expect(seen.get().count == 4)
    }

    @Test func switcherStartsOnFallbackWhenGlasspadIsFrontmost() {
        let observer = FakeFrontmostObserver(current: "app.glasspad.mac")
        let switcher = ProfileSwitcher(observer: observer, profiles: [fallback, safariStarter],
                                       ignoredBundleIDs: ["app.glasspad.mac"])
        let seen = LockedBox<[String?]>([])
        switcher.start { p in seen.update { $0.append(p?.name) } }
        #expect(seen.get() == ["Everywhere"])
    }

    @Test func starterLibraryIsCompleteAndConsistent() {
        let profiles = StarterLibrary.profiles
        let macros = StarterLibrary.macros
        let byID = Dictionary(uniqueKeysWithValues: macros.map { ($0.id, $0) }) // crashes on duplicate ids
        let bundles = Set(profiles.flatMap(\.bundleIDs))
        for app in ["com.apple.Safari", "com.apple.finder", "com.apple.dt.Xcode", "com.apple.FinalCut",
                    "com.apple.iWork.Keynote", "com.apple.Music", "com.figma.Desktop", "com.microsoft.VSCode",
                    "com.tinyspeck.slackmacgap", "us.zoom.xos"] {
            #expect(bundles.contains(app), "missing starter for \(app)")
        }
        #expect(profiles.filter(\.isFallback).count == 1)
        #expect(Set(profiles.map(\.id)).count == profiles.count)
        for p in profiles {
            #expect(p.origin == .starter)
            #expect(!p.macroIDs.isEmpty)
            for id in p.macroIDs {
                let m = byID[id]
                #expect(m != nil)
                guard let m else { continue }
                #expect(m.origin == .starter)
                // Every starter is one keystroke that maps to a real key code.
                guard case .keystroke(let k) = m.steps.first, m.steps.count == 1 else {
                    Issue.record("\(m.name) is not a single keystroke"); continue
                }
                #expect(k.key.ansiKeyCode != nil, "\(m.name) has no key code")
            }
        }
        // Ids are stable across launches so restoring overwrites in place.
        #expect(StarterLibrary.stableID("safari.New Tab") == StarterLibrary.stableID("safari.New Tab"))
        #expect(StarterLibrary.stableID("a") != StarterLibrary.stableID("b"))
    }

    @Test func seedingHappensOnceAndRestoreKeepsUserItems() throws {
        let dir = tempDir()
        let macros = MacroStore(directory: dir.appendingPathComponent("macros"))
        let profiles = ProfileStore(file: dir.appendingPathComponent("profiles.json"))
        #expect(try StarterSeeder.seedIfNeeded(macros: macros, profiles: profiles))
        #expect(macros.loadAll().macros.count == StarterLibrary.macros.count)
        #expect(try profiles.load()?.count == StarterLibrary.profiles.count)

        // The user deletes a starter, edits another and adds a profile.
        let newTab = StarterLibrary.macros.first { $0.name == "New Tab" }!
        try macros.delete(id: newTab.id)
        var edited = StarterLibrary.macros.first { $0.name == "Reload" }!
        edited.color = "#000000"
        try macros.save(edited)
        let mine = ContextProfile(name: "Mine", bundleIDs: ["com.x"], macroIDs: [edited.id])
        try profiles.save((try profiles.load() ?? []) + [mine])

        // Seeding again does nothing: the deleted starter stays deleted.
        #expect(try !StarterSeeder.seedIfNeeded(macros: macros, profiles: profiles))
        #expect(macros.loadAll().macros.count == StarterLibrary.macros.count - 1)

        // Restore brings starters back to shipped state and keeps "Mine".
        try StarterSeeder.restoreStarters(macros: macros, profiles: profiles)
        #expect(try macros.load(id: newTab.id) == newTab)
        #expect(try macros.load(id: edited.id).color != "#000000")
        let after = try profiles.load() ?? []
        #expect(after.count == StarterLibrary.profiles.count + 1)
        #expect(after.contains(mine))
    }
}
