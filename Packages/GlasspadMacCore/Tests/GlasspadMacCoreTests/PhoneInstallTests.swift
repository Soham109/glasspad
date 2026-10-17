import Foundation
import Testing
@testable import GlasspadMacCore

// Reading what the install and renewal scripts leave behind (Settings > iPhone), and the file
// the renewal script reads to tell a suspended iPhone app from one in use.

@Suite struct PhoneInstallTests {
    /// A scratch home folder laid out like the real one.
    private func home() throws -> (URL, PhoneInstallStatus.Paths) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gp install \(UUID().uuidString)")
        let paths = PhoneInstallStatus.Paths(home: dir)
        for url in [paths.installFile, paths.launchAgent] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return (dir, paths)
    }

    @Test func envLine() {
        // As install-phone.sh writes it (printf %q leaves digits bare), among the other lines.
        let env = "GLASSPAD_REPO=/Users/me/Projects/glass\\ pad\nGLASSPAD_INSTALLED_AT=1792000000\nGLASSPAD_REV=abc\n"
        #expect(PhoneInstallStatus.installedAt(env: env) == Date(timeIntervalSince1970: 1_792_000_000))
        #expect(PhoneInstallStatus.installedAt(env: "GLASSPAD_INSTALLED_AT='1792000000'") == Date(timeIntervalSince1970: 1_792_000_000))
        #expect(PhoneInstallStatus.installedAt(env: "GLASSPAD_INSTALLED_AT=$(date +%s)") == nil)
        #expect(PhoneInstallStatus.installedAt(env: "GLASSPAD_INSTALLED_AT=") == nil)
        #expect(PhoneInstallStatus.installedAt(env: "GLASSPAD_INSTALLED_AT=-5") == nil)
        #expect(PhoneInstallStatus.installedAt(env: "GLASSPAD_INSTALLED_ATX=1792000000") == nil)
        #expect(PhoneInstallStatus.installedAt(env: "") == nil)
    }

    @Test func statusJSON() {
        let full = PhoneInstallStatus.check(json: Data(#"{"checkedAt":1792000100,"result":"notReachable","installedAt":1792000000}"#.utf8))
        #expect(full == .init(checkedAt: Date(timeIntervalSince1970: 1_792_000_100), result: .notReachable))
        #expect(full?.result.isProblem == true)
        // The install time there is optional.
        #expect(PhoneInstallStatus.check(json: Data(#"{"checkedAt":1792000100,"result":"renewed"}"#.utf8))?.result == .renewed)
        for bad in [#"{"result":"renewed"}"#, #"{"checkedAt":1792000100}"#, #"{"checkedAt":1792000100,"result":"exploded"}"#,
                    #"{"checkedAt":"soon","result":"failed"}"#, #"{"checkedAt":0,"result":"failed"}"#, "[]", "", "{\"checkedAt\":17920"] {
            #expect(PhoneInstallStatus.check(json: Data(bad.utf8)) == nil, "\(bad)")
        }
        #expect(PhoneInstallStatus.Result.failed.isProblem)
        #expect(!PhoneInstallStatus.Result.waitingInUse.isProblem)
        #expect(!PhoneInstallStatus.Result.tooEarly.isProblem)
    }

    @Test func loadsWhatTheScriptsLeft() throws {
        let (dir, paths) = try home()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PhoneInstallStatus.load(paths) == nil)   // never installed

        try "GLASSPAD_INSTALLED_AT=1792000000\n".write(to: paths.installFile, atomically: true, encoding: .utf8)
        #expect(PhoneInstallStatus.load(paths) == .init(installedAt: Date(timeIntervalSince1970: 1_792_000_000), renewsByItself: false))

        try "<plist/>".write(to: paths.launchAgent, atomically: true, encoding: .utf8)
        try Data(#"{"checkedAt":1792400000,"result":"failed","installedAt":1792000000}"#.utf8).write(to: paths.statusFile)
        let loaded = try #require(PhoneInstallStatus.load(paths))
        #expect(loaded.renewsByItself)
        #expect(loaded.lastCheck?.result == .failed)

        // Installed again by hand after that run: its failure no longer applies.
        try "GLASSPAD_INSTALLED_AT=1792500000\n".write(to: paths.installFile, atomically: true, encoding: .utf8)
        #expect(PhoneInstallStatus.load(paths)?.lastCheck == nil)

        // A broken status file is the same as none.
        try Data("half a fi".utf8).write(to: paths.statusFile)
        #expect(PhoneInstallStatus.load(paths)?.lastCheck == nil)
        try "GLASSPAD_INSTALLED_AT=garbage\n".write(to: paths.installFile, atomically: true, encoding: .utf8)
        #expect(PhoneInstallStatus.load(paths) == nil)
    }

    @Test func sessionFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gp session \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = PhoneSessionFile(url: dir.appendingPathComponent("Glasspad/phone-session.json"))
        func read() throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        }
        // Starting with no phone and no file: the phone has not been here, so no recent session.
        file.record(active: false, now: Date(timeIntervalSince1970: 1_792_000_000))
        #expect(try read()["active"] as? Bool == false)
        #expect(try read()["endedAt"] as? Int == 1_792_000_000)
        // Starting again later with no phone keeps the old end time.
        file.record(active: false, now: Date(timeIntervalSince1970: 1_792_009_000))
        #expect(try read()["endedAt"] as? Int == 1_792_000_000)

        file.record(active: true, now: Date(timeIntervalSince1970: 1_792_010_000))
        #expect(try read()["active"] as? Bool == true)
        #expect(try read()["endedAt"] == nil)
        file.record(active: false, now: Date(timeIntervalSince1970: 1_792_012_345.7))
        #expect(try read()["active"] as? Bool == false)
        #expect(try read()["endedAt"] as? Int == 1_792_012_345)   // whole seconds, for the script

        // A session left marked active (the app stopped while connected) ends at the next start.
        file.record(active: true, now: Date(timeIntervalSince1970: 1_792_020_000))
        file.record(active: false, now: Date(timeIntervalSince1970: 1_792_090_000))
        #expect(try read()["endedAt"] as? Int == 1_792_090_000)
        // Text the script reads as plain words and digits.
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "{\"active\":false,\"endedAt\":1792090000}\n")
    }
}
