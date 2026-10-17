import Foundation
import Testing
@testable import GlasspadKit

@Suite struct ActivityLogTests {
    private func tempLog() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("glasspad-activity-\(UUID().uuidString)/Logs/Glasspad/activity.log")
    }

    private func fixedLog() -> ActivityLog {
        ActivityLog(clock: { Date(timeIntervalSince1970: 1_800_000_000.25) }, timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test func offUntilStarted() {
        let log = fixedLog()
        log.record("media", ["cmd": "playPause"])
        log.flush()
        #expect(log.fileURL == nil)
        #expect(log.contents().isEmpty)
    }

    @Test func linesAreTimeCategoryAndFields() throws {
        let url = tempLog()
        let log = fixedLog()
        log.start(at: url)
        log.record("media", ["cmd": "playPause", "route": "adapter", "ok": "true", "np": "com.google.Chrome", "front": nil])
        log.flush()
        #expect(log.contents() == "2027-01-15T08:00:00.250Z media cmd=playPause route=adapter ok=true np=com.google.Chrome\n")
        #expect(log.fileURL == url)
    }

    @Test func valuesCannotBreakTheLineOrRunLong() {
        #expect(ActivityLog.clean("a b\nc\td") == "a_b_c_d")
        #expect(ActivityLog.clean("") == "-")
        #expect(ActivityLog.clean("x\u{7}y") == "xy")
        let long = ActivityLog.clean(String(repeating: "z", count: 500))
        #expect(long.count == ActivityLog.maxValueLength)
        #expect(long.hasSuffix("…"))
        let line = ActivityLog.line(time: "T", category: "link", fields: [("reason", "closed\nby peer")])
        #expect(line == "T link reason=closed_by_peer\n")
    }

    @Test func folderAndFileArePrivate() throws {
        let url = tempLog()
        let log = fixedLog()
        log.start(at: url)
        log.record("link", ["state": "connected"])
        log.flush()
        let fm = FileManager.default
        let file = try #require(try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        let dir = try #require(try fm.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)
        #expect(file.intValue == 0o600)
        #expect(dir.intValue == 0o700)
    }

    /// The ring: the file never passes the cap, keeps whole lines, and keeps the newest.
    @Test func cappedKeepingTheNewestWholeLines() throws {
        let url = tempLog()
        let log = fixedLog()
        let cap = 4096
        log.start(at: url, maxBytes: cap)
        for i in 0..<1000 {
            log.record("media", ["n": String(i)])
            if i % 100 == 0 {
                log.flush()
                let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)
                #expect(size.intValue <= cap)
            }
        }
        log.flush()
        let text = log.contents()
        #expect(text.utf8.count <= cap)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.hasPrefix("2027-01-15T08:00:00.250Z media n=") })
        #expect(lines.last == "2027-01-15T08:00:00.250Z media n=999")
        // In order, with no gaps: the oldest lines went, nothing in between.
        let numbers = lines.compactMap { Int($0.split(separator: "=").last ?? "") }
        #expect(numbers == Array((1000 - numbers.count)..<1000))
    }

    @Test func survivesTheFileBeingDeleted() throws {
        let url = tempLog()
        let log = fixedLog()
        log.start(at: url)
        log.record("app", ["side": "mac"])
        log.flush()
        try FileManager.default.removeItem(at: url)
        log.record("app", ["n": "1"])
        log.record("app", ["n": "2"])
        log.flush()
        #expect(log.contents().contains("app n=2"))
    }

    @Test func appendsAcrossRestarts() {
        let url = tempLog()
        let first = fixedLog()
        first.start(at: url)
        first.record("app", ["run": "1"])
        first.flush()
        let second = fixedLog()
        second.start(at: url)
        second.record("app", ["run": "2"])
        second.flush()
        #expect(second.contents().components(separatedBy: "\n").filter { !$0.isEmpty }.count == 2)
    }

    @Test func linkStateNames() {
        #expect(LinkState.connected(rttMs: 3).logName == "connected")
        #expect(LinkState.failed("refused").logName == "failed")
        #expect(LinkState.failed("refused").failureReason == "refused")
        #expect(LinkState.searching.failureReason == nil)
    }
}
