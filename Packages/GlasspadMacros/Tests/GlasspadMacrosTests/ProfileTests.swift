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
        for app in ["com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox", "com.brave.Browser",
                    "com.microsoft.edgemac", "com.apple.Notes", "com.apple.mail", "com.apple.MobileSMS", "com.apple.iCal",
                    "com.apple.reminders", "com.apple.Preview", "com.apple.Photos", "com.apple.iWork.Pages", "com.apple.Pages",
                    "com.apple.iWork.Numbers", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
                    "com.todesktop.230313mzl4w4u92", "com.spotify.client", "notion.id", "md.obsidian", "com.hnc.Discord",
                    "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.microsoft.Word", "com.microsoft.Excel",
                    "com.microsoft.Powerpoint", "com.microsoft.Outlook", "com.microsoft.teams2", "com.adobe.Photoshop",
                    "com.adobe.illustrator", "com.adobe.PremierePro.26", "com.apple.logic10", "com.apple.garageband10",
                    "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc", "com.apple.TV", "com.linear",
                    "com.openai.chat", "com.anthropic.claudefordesktop", "com.apple.Keynote",
                    "com.apple.Safari", "com.apple.finder", "com.apple.dt.Xcode", "com.apple.FinalCut",
                    "com.apple.iWork.Keynote", "com.apple.Music", "com.figma.Desktop", "com.microsoft.VSCode",
                    "com.tinyspeck.slackmacgap", "us.zoom.xos"] {
            #expect(bundles.contains(app), "missing starter for \(app)")
        }
        #expect(profiles.filter(\.isFallback).count == 1)
        // No app is claimed by two starter profiles.
        let all = profiles.flatMap(\.bundleIDs)
        #expect(Set(all).count == all.count)
        // The fallback brings window tiling and Do Not Disturb.
        let fallback = profiles.first(where: \.isFallback)!
        let controls = fallback.macroIDs.compactMap { byID[$0] }.compactMap { m -> String? in
            if case .macControl(let id) = m.steps.first { return id }
            return nil
        }
        for id in ["windowSplit", "windowLeft", "windowRight", "doNotDisturb"] { #expect(controls.contains(id)) }
        #expect(Set(profiles.map(\.id)).count == profiles.count)
        for p in profiles {
            #expect(p.origin == .starter)
            #expect(!p.macroIDs.isEmpty)
            for id in p.macroIDs {
                let m = byID[id]
                #expect(m != nil)
                guard let m else { continue }
                #expect(m.origin == .starter)
                // Every starter is one keystroke that maps to a real key code, or one Mac control.
                #expect(m.steps.count == 1, "\(m.name) is not a single step")
                switch m.steps.first {
                case .keystroke(let k): #expect(k.key.ansiKeyCode != nil, "\(m.name) has no key code")
                case .macControl(let id): #expect(!id.isEmpty)
                default: Issue.record("\(m.name) is not a keystroke or a Mac control")
                }
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

        // A newer Glasspad with the same starters version changes nothing either.
        #expect(try !StarterSeeder.seedIfNeeded(macros: macros, profiles: profiles))

        // Restore brings starters back to shipped state and keeps "Mine".
        try StarterSeeder.restoreStarters(macros: macros, profiles: profiles)
        #expect(try macros.load(id: newTab.id) == newTab)
        #expect(try macros.load(id: edited.id).color != "#000000")
        let after = try profiles.load() ?? []
        #expect(after.count == StarterLibrary.profiles.count + 1)
        #expect(after.contains(mine))
    }

    // MARK: Upgrading starters

    /// A Mac set up by the first release: version 1 starters and only the old marker.
    private func versionOneMac() throws -> (MacroStore, ProfileStore, URL) {
        let dir = tempDir()
        let macros = MacroStore(directory: dir.appendingPathComponent("macros"))
        let profiles = ProfileStore(file: dir.appendingPathComponent("profiles.json"))
        for m in StarterLibrary.macros(from: StarterLibrary.version1) { try macros.save(m) }
        try profiles.save(StarterLibrary.profiles(from: StarterLibrary.version1))
        try Data().write(to: dir.appendingPathComponent(StarterSeeder.markerName))
        return (macros, profiles, dir)
    }

    @Test func untouchedVersionOneStartersBecomeTheNewOnes() throws {
        let (macros, profiles, _) = try versionOneMac()
        #expect(try StarterSeeder.seedIfNeeded(macros: macros, profiles: profiles))
        let saved = try profiles.load() ?? []
        #expect(Set(saved) == Set(StarterLibrary.profiles))
        #expect(Set(macros.loadAll().macros) == Set(StarterLibrary.macros))
        // Done once.
        #expect(try !StarterSeeder.seedIfNeeded(macros: macros, profiles: profiles))
    }

    @Test func upgradeKeepsTheUsersEditsDeletionsAndProfiles() throws {
        let (macros, profiles, _) = try versionOneMac()
        let v1 = StarterLibrary.macros(from: StarterLibrary.version1)
        let safariID = StarterLibrary.stableID("profile.safari")
        // Edited: Safari's Reload gets a new colour. Deleted: Safari's Reader.
        var reload = v1.first { $0.id == StarterLibrary.stableID("safari.Reload") }!
        reload.color = "#123456"
        try macros.save(reload)
        let reader = StarterLibrary.stableID("safari.Reader")
        try macros.delete(id: reader)
        // The user reordered Safari's profile and dropped Reader from it.
        var all = try profiles.load()!
        let si = all.firstIndex { $0.id == safariID }!
        all[si].macroIDs = all[si].macroIDs.filter { $0 != reader }.reversed()
        let mine = ContextProfile(name: "Mine", bundleIDs: ["com.x"], macroIDs: [reload.id])
        try profiles.save(all + [mine])
        let userOrder = all[si].macroIDs

        try StarterSeeder.upgrade(from: 1, macros: macros, profiles: profiles)

        #expect(try macros.load(id: reload.id).color == "#123456")
        #expect((try? macros.load(id: reader)) == nil)
        let after = try profiles.load()!
        #expect(after.contains(mine))
        let safari = after.first { $0.id == safariID }!
        // The user's order stays first; buttons new in version 2 follow; Reader does not return.
        // (Starters version 2 dropped, such as New Tab, leave it when untouched.)
        let kept = userOrder.filter { (try? macros.load(id: $0)) != nil }
        #expect(kept.count < userOrder.count)
        #expect(Array(safari.macroIDs.prefix(kept.count)) == kept)
        let newInV2 = StarterLibrary.profiles.first { $0.id == safariID }!.macroIDs
            .filter { !StarterLibrary.profiles(from: StarterLibrary.version1).first { $0.id == safariID }!.macroIDs.contains($0) }
        #expect(!newInV2.isEmpty)
        #expect(Array(safari.macroIDs.dropFirst(kept.count)) == newInV2)
        #expect(!safari.macroIDs.contains(reader))
        // Profiles for apps that had none appear.
        #expect(after.contains { $0.id == StarterLibrary.stableID("profile.chrome") })
        // An untouched v1 starter that version 2 dropped is gone (Everywhere's Lock Screen).
        let lock = StarterLibrary.stableID("global.Lock Screen")
        #expect((try? macros.load(id: lock)) == nil)
        #expect(!after.contains { $0.macroIDs.contains(lock) })
    }

    @Test func droppedStarterThatTheUserReusesIsKept() throws {
        let (macros, profiles, _) = try versionOneMac()
        let lock = StarterLibrary.stableID("global.Lock Screen")
        let mine = ContextProfile(name: "Mine", bundleIDs: ["com.x"], macroIDs: [lock])
        try profiles.save((try profiles.load() ?? []) + [mine])
        try StarterSeeder.upgrade(from: 1, macros: macros, profiles: profiles)
        #expect((try? macros.load(id: lock)) != nil)
    }

    @Test func versionOneIsKeptExactlyAsShipped() {
        // The upgrade compares against what version 1 wrote, so this list must never change.
        let v1 = StarterLibrary.profiles(from: StarterLibrary.version1)
        #expect(v1.count == 11)
        #expect(StarterLibrary.macros(from: StarterLibrary.version1).count == 96)
        #expect(StarterLibrary.definitions(version: 1) != nil && StarterLibrary.definitions(version: StarterLibrary.version) != nil)
    }
}
