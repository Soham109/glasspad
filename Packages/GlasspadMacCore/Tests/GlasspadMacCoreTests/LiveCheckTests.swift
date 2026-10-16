import Foundation
import Testing
@testable import GlasspadKit
@testable import GlasspadMacCore

/// The live check's own logic, on a pretend Mac: reading the state, putting it back, the runner
/// and the report. The check itself only ever runs by hand (scripts/live-check.sh).
@Suite @MainActor struct LiveCheckTests {
    private func header() -> LiveCheckReport.Header {
        LiveCheckReport.Header(started: Date(timeIntervalSince1970: 1_800_000_000), mac: "Test Mac", system: "macOS 26.0",
                               app: "0.1.0 (1)", displays: 2, disruptive: false)
    }

    private func runner(_ mac: FakeLiveCheckMac, steps: [LiveCheckStep], disruptive: Bool = false) -> (LiveCheckRunner, URL) {
        let folder = tempURL("logs")
        return (LiveCheckRunner(steps: steps, mac: mac, includeDisruptive: disruptive, header: header(), folder: folder), folder)
    }

    private func step(_ id: String) -> LiveCheckStep { LiveCheckSteps.all().first { $0.id == id }! }

    /// Runs every step, answering each question with `answer`.
    private func runAll(_ r: LiveCheckRunner, answer: Bool = true) async {
        r.start()
        while r.phase != .finished {
            switch r.phase {
            case .ready: await r.run()
            case .asking: await r.answer(answer)
            default: Issue.record("stuck in \(r.phase)"); return
            }
        }
    }

    // MARK: Snapshot and restore

    @Test func restoringPutsBackEverythingAStepChanged() async {
        let mac = FakeLiveCheckMac()
        _ = await mac.openTestWindows()
        let before = mac.everything
        let windows = mac.windows
        let snap = await LiveCheckSnapshot.capture(mac, playback: true)
        mac.dark = true; mac.night = true; mac.awake = true; _ = await mac.flipDoNotDisturb(); mac.ncWindows = 1
        mac.volume = 0.1; mac.muted = true; mac.micMuted = true; mac.micVolume = 0.2; mac.bright = 0.2
        mac.setDock(LiveCheckDock(hidden: true, hideWhileConnected: false, connected: false, isHiddenNow: true))
        mac.recording = true; mac.playing = false
        mac.windows[0] = CGRect(x: 0, y: 0, width: 300, height: 300)

        let notes = await LiveCheckRestorer.restore(snap, on: mac)
        #expect(notes.allSatisfy { $0.ok })
        #expect(notes.count == 14)
        #expect(mac.everything == before)
        #expect(mac.windows == windows)
        #expect(mac.doNotDisturbFlips == 2)
    }

    @Test func nothingChangedMeansNothingToPutBack() async {
        let mac = FakeLiveCheckMac()
        let snap = await LiveCheckSnapshot.capture(mac)
        #expect(await LiveCheckRestorer.restore(snap, on: mac).isEmpty)
        #expect(mac.log.isEmpty)
    }

    @Test func doNotDisturbIsSwitchedBackOnlyAfterAnOddNumberOfSwitches() async {
        let mac = FakeLiveCheckMac()
        let snap = await LiveCheckSnapshot.capture(mac)
        _ = await mac.flipDoNotDisturb()
        _ = await mac.flipDoNotDisturb()
        #expect(await LiveCheckRestorer.restore(snap, on: mac).isEmpty)
        _ = await mac.flipDoNotDisturb()
        let notes = await LiveCheckRestorer.restore(snap, on: mac)
        #expect(notes == [LiveCheckRestoreNote(ok: true, "Switched Do Not Disturb back")])
        #expect(mac.dnd == false)
    }

    @Test func aRestoreThatDidNotWorkIsSaidSo() async {
        let mac = FakeLiveCheckMac()
        mac.stuck = ["dark"]
        let snap = await LiveCheckSnapshot.capture(mac)
        mac.dark = true
        let notes = await LiveCheckRestorer.restore(snap, on: mac)
        #expect(notes == [LiveCheckRestoreNote(ok: false, "Could not put back Light appearance")])
    }

    @Test func displaysGoBackToTheirSizeMirroringAndPlace() async {
        let mac = FakeLiveCheckMac()
        let original = mac.displays
        let snap = await LiveCheckSnapshot.capture(mac)
        _ = mac.phone(.displayCommand(id: UUID(), command: .resolution(display: 1, id: 12)))
        _ = mac.applyDisplays(.origins([DisplayOrigin(display: 2, origin: .zero), DisplayOrigin(display: 1, origin: CGPoint(x: 2560, y: 0))]),
                              permanently: true)
        #expect(mac.displays != original)
        let notes = await LiveCheckRestorer.restore(snap, on: mac)
        #expect(notes.allSatisfy { $0.ok })
        #expect(mac.displays == original)
        // The change waiting for Keep was reverted first, the way the Revert button does it.
        #expect(mac.log.contains { $0.contains("revertChanges") })
    }

    // MARK: Runner

    @Test func aQuestionIsAskedAndTheMacIsPutBackWhateverTheAnswer() async throws {
        for answer in [true, false] {
            let mac = FakeLiveCheckMac()
            let (r, folder) = runner(mac, steps: [step("dark-mode")])
            r.start()
            await r.run()
            guard case .asking(let question, let observed) = r.phase else { Issue.record("not asking"); return }
            #expect(question == "Did the Mac switch to Dark?")
            #expect(observed == ["Glasspad said: Dark", "Appearance: Light, now Dark"])
            #expect(mac.dark == true)
            await r.answer(answer, note: answer ? "  " : "It flickered")
            #expect(mac.dark == false)
            #expect(r.phase == .finished)
            let record = try #require(r.records.first)
            #expect(record.verdict == (answer ? .pass : .fail))
            #expect(record.restored == [LiveCheckRestoreNote(ok: true, "Put back Light appearance")])
            #expect(record.note == (answer ? nil : "It flickered"))
            let report = try String(contentsOf: try #require(r.reportURL), encoding: .utf8)
            #expect(r.reportURL?.deletingLastPathComponent().path == folder.path)
            #expect(report.contains("| Dark Mode | \(answer ? "Pass" : "Fail") |"))
            #expect(mac.log.last == "wrap up")
        }
    }

    @Test func whatTheMacCanTellOverridesAYes() async {
        let mac = FakeLiveCheckMac()
        mac.night = nil
        let broken = LiveCheckStep(id: "x", group: "Mac", title: "Broken", summary: "") { _ in
            LiveCheckTrial(observed: ["no"], verified: false, question: "Did it work?")
        }
        let (r, _) = runner(mac, steps: [broken])
        r.start()
        await r.run()
        // A step the Mac already knows failed is not asked about.
        #expect(r.phase == .finished)
        #expect(r.records.first?.verdict == .fail)
    }

    @Test func stoppingWhileAskingStillPutsThingsBack() async throws {
        let mac = FakeLiveCheckMac()
        let (r, _) = runner(mac, steps: [step("night-shift"), step("dark-mode")])
        r.start()
        await r.run()
        #expect(mac.night == true)
        await r.stop()
        #expect(mac.night == false)
        #expect(r.phase == .finished)
        #expect(r.records.map(\.verdict) == [.fail])
        #expect(r.records.first?.note == "Stopped before answering")
        let report = try String(contentsOf: try #require(r.reportURL), encoding: .utf8)
        #expect(report.contains("## Not run\n\n- Dark Mode\n"))
    }

    @Test func quittingBeforeStartingChangesNothingAndWritesNoReport() async {
        let mac = FakeLiveCheckMac()
        let (r, folder) = runner(mac, steps: LiveCheckSteps.all())
        await r.stop()
        #expect(r.phase == .finished)
        #expect(r.reportURL == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(mac.log.isEmpty)
    }

    @Test func disruptiveStepsAreLeftOutUnlessAskedFor() {
        let mac = FakeLiveCheckMac()
        let quiet = runner(mac, steps: LiveCheckSteps.all()).0
        #expect(!quiet.steps.contains { $0.disruptive })
        #expect(!quiet.steps.contains { $0.id == "lock-screen" })
        let all = runner(mac, steps: LiveCheckSteps.all(), disruptive: true).0
        #expect(Set(all.steps.filter(\.disruptive).map(\.id)) == ["lock-screen", "sleep-display", "sleep-mac", "empty-trash", "eject-all"])
    }

    @Test func aStepThatCannotRunHereIsSkippedWithTheReason() async {
        let mac = FakeLiveCheckMac()
        mac.displays.removeLast()
        let (r, _) = runner(mac, steps: [step("window-next-display")])
        r.start()
        #expect(r.currentUnavailable == "Only one display is connected")
        await r.run()
        #expect(r.records == [LiveCheckRecord(group: "Windows", title: "Next Display", verdict: .skipped,
                                              observed: ["Only one display is connected"])])
        #expect(mac.windows.isEmpty)
    }

    @Test func filesAStepMadeGoToTheTrash() async {
        let mac = FakeLiveCheckMac()
        let (r, _) = runner(mac, steps: [step("screenshots"), step("screen-recording")])
        await runAll(r)
        #expect(r.records.map(\.verdict) == [.pass, .pass])
        #expect(mac.files.isEmpty)
        #expect(mac.trashed.count == 3)
        #expect(r.records[0].restored.first?.text == "Moved the 2 files it made to the Trash")
    }

    /// Every step on the pretend Mac: each one passes and the Mac ends exactly as it started.
    @Test func theWholeCheckPassesAndLeavesTheMacAsItWas() async {
        let mac = FakeLiveCheckMac()
        let before = mac.everything
        let (r, _) = runner(mac, steps: LiveCheckSteps.all(), disruptive: true)
        await runAll(r)
        let failed = r.records.filter { $0.verdict == .fail }.map { "\($0.title): \($0.observed)" }
        #expect(failed == [])
        // Spotify and the video players are not installed on the pretend Mac.
        #expect(r.records.filter { $0.verdict == .skipped }.map(\.title) == ["Spotify", "TV", "QuickTime Player", "IINA", "VLC", "Infuse"])
        #expect(r.records.flatMap(\.restored).allSatisfy { $0.ok })
        #expect(mac.everything == before)
        #expect(mac.windows.isEmpty)
        #expect(r.records.count == r.steps.count)
    }

    @Test func theResolutionGoesBackByItselfAfterFifteenSeconds() async throws {
        let mac = FakeLiveCheckMac()
        let start = mac.clock
        let (r, _) = runner(mac, steps: [step("displays-resolution")])
        r.start()
        await r.run()
        guard case .asking(_, let observed) = r.phase else { Issue.record("not asking"); return }
        #expect(observed.contains("Size after 2.5 s: 1800 × 1169"))
        #expect(observed.contains("After 18 s: back to 1512 × 982"))
        #expect(mac.clock.timeIntervalSince(start) >= Double(DisplaysMode.keepSeconds))
        await r.answer(true)
        #expect(r.records.first?.verdict == .pass)
    }

    // MARK: Steps

    @Test func windowStepsUseTheTestWindowAndExpectMacOSsFrame() async throws {
        let mac = FakeLiveCheckMac()
        let (r, _) = runner(mac, steps: [step("window-windowLeft")])
        r.start()
        await r.run()
        let record = try #require(r.records.first)
        #expect(record.verdict == .pass)
        #expect(record.observed.last == "Expected: 8, 40, 744 × 934")
        #expect(record.restored == [LiveCheckRestoreNote(ok: true, "Put the test window back")])
    }

    @Test func remotePressesFollowThePlayer() {
        let music = LiveCheckSteps.remotePresses(RemoteKeymap(player: .appleMusic), canSeek: true).map(\.words)
        #expect(music == ["pause", "play", "skip to the next song", "go back a song", "go full screen", "leave full screen"])
        let youtube = LiveCheckSteps.remotePresses(RemoteKeymap(player: .browser(.youtube)), canSeek: false).map(\.words)
        #expect(youtube.contains("jump forward") && youtube.contains("turn subtitles on"))
    }

    @Test func arrangingMovesTheOtherDisplayToTheFarSide() {
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(LiveCheckSteps.oppositeSide(of: CGRect(x: 1512, y: 0, width: 2560, height: 1440), around: main) == CGPoint(x: -2560, y: 0))
        #expect(LiveCheckSteps.oppositeSide(of: CGRect(x: -1920, y: 100, width: 1920, height: 1080), around: main) == CGPoint(x: 1512, y: 100))
        #expect(LiveCheckSteps.oppositeSide(of: CGRect(x: 0, y: -1080, width: 1920, height: 1080), around: main) == CGPoint(x: 0, y: 982))
    }

    // MARK: Report

    @Test func reportNamesCountUpWithinADay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_792_022_400) // 2026-10-15
        #expect(LiveCheckReport.fileName(date: date, existing: [], calendar: cal) == "live-check-2026-10-15.md")
        #expect(LiveCheckReport.fileName(date: date, existing: ["live-check-2026-10-15.md", "live-check-2026-10-15-2.md"], calendar: cal)
                == "live-check-2026-10-15-3.md")
    }

    @Test func reportGroupsFeaturesAndListsWhatWasNotPutBack() {
        let records = [
            LiveCheckRecord(group: "Mac", title: "Dark Mode", verdict: .pass, observed: ["Glasspad said: Dark"],
                            restored: [LiveCheckRestoreNote(ok: true, "Put back Light appearance")]),
            LiveCheckRecord(group: "Sound", title: "Mute", verdict: .fail, observed: ["a | b"],
                            restored: [LiveCheckRestoreNote(ok: false, "Could not unmute the sound again")], note: "No sound"),
            LiveCheckRecord(group: "Mac", title: "Keep Awake", verdict: .skipped),
        ]
        let md = LiveCheckReport.markdown(header(), records: records, finished: true)
        #expect(md.contains("- 1 passed, 1 failed, 1 skipped\n"))
        #expect(md.contains("**Not put back:**\n\n- Could not unmute the sound again\n"))
        #expect(md.contains("## Mac\n\n| Feature | Result | Notes |\n| --- | --- | --- |\n| Dark Mode | Pass | Glasspad said: Dark<br>Put back Light appearance |\n| Keep Awake | Skipped |  |\n"))
        #expect(md.contains("| Mute | Fail | a \\| b<br>Not put back: Could not unmute the sound again<br>Note: No sound |"))
        #expect(!md.contains("\u{2014}") && !md.contains("\u{2013}"))
    }

    @Test func noStepTextUsesDashes() {
        for s in LiveCheckSteps.all() {
            for text in [s.title, s.summary, s.getReady ?? ""] {
                #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
            }
        }
        #expect(Set(LiveCheckSteps.all().map(\.id)).count == LiveCheckSteps.all().count)
    }
}
