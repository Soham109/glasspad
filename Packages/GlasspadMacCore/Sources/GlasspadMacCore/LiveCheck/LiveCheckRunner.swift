import Combine
import Foundation
import GlasspadKit

/// One feature to try on the real Mac.
@MainActor
public struct LiveCheckStep: Identifiable {
    public let id: String
    public let group: String
    public let title: String
    /// What it will do, shown before Run.
    public let summary: String
    /// Locks, sleeps, empties or ejects: left out unless the check was started with them.
    public let disruptive: Bool
    /// What to do before pressing Run ("Start a song in Music"), if anything.
    public let getReady: String?
    /// Runs on the check's own TextEdit windows, opened first.
    public let needsTestWindows: Bool
    /// Read whether something is playing before, and put it back after.
    public let touchesPlayback: Bool
    /// Why it cannot run on this Mac (one display, an app that is not installed), else nil.
    public let unavailable: @MainActor (LiveCheckMac) -> String?
    public let perform: @MainActor (LiveCheckRun) async -> LiveCheckTrial

    public init(id: String, group: String, title: String, summary: String, getReady: String? = nil,
                disruptive: Bool = false, needsTestWindows: Bool = false, touchesPlayback: Bool = false, unavailable: @escaping @MainActor (LiveCheckMac) -> String? = { _ in nil },
                perform: @escaping @MainActor (LiveCheckRun) async -> LiveCheckTrial) {
        self.id = id
        self.group = group
        self.title = title
        self.summary = summary
        self.getReady = getReady
        self.disruptive = disruptive
        self.needsTestWindows = needsTestWindows
        self.touchesPlayback = touchesPlayback
        self.unavailable = unavailable
        self.perform = perform
    }
}

/// What a running step can reach: the Mac, and a line under the title saying what it is doing.
@MainActor
public struct LiveCheckRun {
    public let mac: LiveCheckMac
    public let say: @MainActor (String) -> Void
}

/// What a step saw.
public struct LiveCheckTrial: Sendable {
    /// Readings, shown to the person and written to the report.
    public var observed: [String]
    /// What the Mac itself could tell: false fails the step whatever the answer. nil when it
    /// cannot tell.
    public var verified: Bool?
    /// Asked when only the person can see it; nil when `verified` decides.
    public var question: String?
    /// Files the step made, moved to the Trash afterwards.
    public var made: [URL]

    public init(observed: [String] = [], verified: Bool? = nil, question: String? = nil, made: [URL] = []) {
        self.observed = observed
        self.verified = verified
        self.question = question
        self.made = made
    }
}

public enum LiveCheckVerdict: String, Sendable {
    case pass = "Pass"
    case fail = "Fail"
    case skipped = "Skipped"
}

/// One line of the report.
public struct LiveCheckRecord: Equatable, Sendable {
    public var group: String
    public var title: String
    public var verdict: LiveCheckVerdict
    public var observed: [String]
    public var restored: [LiveCheckRestoreNote]
    public var note: String?

    public init(group: String, title: String, verdict: LiveCheckVerdict, observed: [String] = [],
                restored: [LiveCheckRestoreNote] = [], note: String? = nil) {
        self.group = group
        self.title = title
        self.verdict = verdict
        self.observed = observed
        self.restored = restored
        self.note = note
    }

    /// Pass only when the Mac and the person agree; a missing answer is a fail.
    static func verdict(_ trial: LiveCheckTrial, answer: Bool?) -> LiveCheckVerdict {
        if trial.verified == false { return .fail }
        if trial.question != nil { return answer == true ? .pass : .fail }
        return trial.verified == true ? .pass : .fail
    }
}

// MARK: - Report

/// The Markdown report, ~/Library/Logs/Glasspad/live-check-<date>.md.
public enum LiveCheckReport {
    public static func folder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Logs/Glasspad", isDirectory: true)
    }

    /// live-check-2026-10-16.md, then -2, -3 for later runs the same day.
    public static func fileName(date: Date, existing: Set<String>, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        var name = "live-check-\(day).md"
        var n = 2
        while existing.contains(name) {
            name = "live-check-\(day)-\(n).md"
            n += 1
        }
        return name
    }

    public struct Header: Sendable {
        public var started: Date
        public var mac: String
        public var system: String
        public var app: String
        public var displays: Int
        public var disruptive: Bool

        public init(started: Date, mac: String, system: String, app: String, displays: Int, disruptive: Bool) {
            self.started = started
            self.mac = mac
            self.system = system
            self.app = app
            self.displays = displays
            self.disruptive = disruptive
        }
    }

    public static func markdown(_ header: Header, records: [LiveCheckRecord], notRun: [String] = [], finished: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let passed = records.filter { $0.verdict == .pass }.count
        let failed = records.filter { $0.verdict == .fail }.count
        let skipped = records.filter { $0.verdict == .skipped }.count
        var out = "# Glasspad live check, \(f.string(from: header.started))\n\n"
        out += "- Mac: \(header.mac), \(header.system)\n"
        out += "- Glasspad: \(header.app)\n"
        out += "- Displays: \(header.displays)\n"
        out += "- Lock, sleep, Empty Trash and Eject: \(header.disruptive ? "included" : "left out")\n"
        out += "- \(passed) passed, \(failed) failed, \(skipped) skipped\(finished ? "" : ", still running")\n"
        let unrestored = records.flatMap(\.restored).filter { !$0.ok }
        if !unrestored.isEmpty {
            out += "\n**Not put back:**\n\n" + unrestored.map { "- \($0.text)\n" }.joined()
        }
        var groups: [String] = []
        for r in records where !groups.contains(r.group) { groups.append(r.group) }
        for g in groups {
            out += "\n## \(g)\n\n| Feature | Result | Notes |\n| --- | --- | --- |\n"
            for r in records where r.group == g {
                var notes = r.observed
                notes += r.restored.map { $0.ok ? $0.text : "Not put back: \($0.text)" }
                if let n = r.note, !n.isEmpty { notes.append("Note: \(n)") }
                out += "| \(cell(r.title)) | \(r.verdict.rawValue) | \(notes.map(cell).joined(separator: "<br>")) |\n"
            }
        }
        if !notRun.isEmpty {
            out += "\n## Not run\n\n" + notRun.map { "- \($0)\n" }.joined()
        }
        return out
    }

    /// Keeps a table cell in one piece.
    static func cell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Runner

/// Walks through the steps one at a time: says what the next one does, waits for Run or Skip,
/// runs it, asks when only the person can tell, and always puts the Mac back before the next
/// one. The report is written after every step, so stopping half way still leaves one.
@MainActor
public final class LiveCheckRunner: ObservableObject {
    public enum Phase: Equatable {
        case intro
        /// Waiting for Run or Skip on `steps[index]`.
        case ready
        case running(String)
        /// The step ran; only the person can say whether it worked.
        case asking(question: String, observed: [String])
        case finished
    }

    @Published public private(set) var phase: Phase = .intro
    @Published public private(set) var index = 0
    @Published public private(set) var records: [LiveCheckRecord] = []
    @Published public private(set) var reportURL: URL?
    /// Why the report could not be written, if it could not.
    @Published public private(set) var reportError: String?

    public let steps: [LiveCheckStep]
    public let includesDisruptive: Bool
    private let mac: LiveCheckMac
    private let header: LiveCheckReport.Header
    private let folder: URL
    private var pending: (step: LiveCheckStep, trial: LiveCheckTrial, snapshot: LiveCheckSnapshot)?

    /// Disruptive steps are dropped unless `includeDisruptive`.
    public init(steps: [LiveCheckStep], mac: LiveCheckMac, includeDisruptive: Bool, header: LiveCheckReport.Header,
                folder: URL = LiveCheckReport.folder()) {
        self.steps = steps.filter { includeDisruptive || !$0.disruptive }
        self.includesDisruptive = includeDisruptive
        self.mac = mac
        self.header = header
        self.folder = folder
    }

    public var current: LiveCheckStep? { steps.indices.contains(index) ? steps[index] : nil }

    /// Why the current step cannot run here, else nil. Read once per step, when it comes up.
    @Published public private(set) var currentUnavailable: String?

    public var last: LiveCheckRecord? { records.last }

    public func start() {
        guard phase == .intro else { return }
        currentUnavailable = current.flatMap { $0.unavailable(mac) }
        phase = steps.isEmpty ? .finished : .ready
        writeReport(finished: steps.isEmpty)
    }

    public func skip() async {
        guard phase == .ready, let step = current else { return }
        records.append(LiveCheckRecord(group: step.group, title: step.title, verdict: .skipped,
                                       observed: currentUnavailable.map { [$0] } ?? []))
        await advance()
    }

    public func run() async {
        guard phase == .ready, let step = current else { return }
        if currentUnavailable != nil { return await skip() }
        phase = .running("Getting ready")
        if step.needsTestWindows, mac.testWindowCount < 2 {
            phase = .running("Opening two TextEdit windows to test with")
            guard await mac.openTestWindows() else {
                mac.returnToCheck()
                records.append(LiveCheckRecord(group: step.group, title: step.title, verdict: .fail,
                                               observed: ["Could not open the TextEdit test windows, so nothing was moved"]))
                return await advance()
            }
        }
        let snapshot = await LiveCheckSnapshot.capture(mac, playback: step.touchesPlayback)
        let trial = await step.perform(LiveCheckRun(mac: mac, say: { [weak self] in self?.phase = .running($0) }))
        mac.returnToCheck()
        pending = (step, trial, snapshot)
        if let question = trial.question, trial.verified != false {
            phase = .asking(question: question, observed: trial.observed)
        } else {
            await finishStep(answer: nil, note: nil)
        }
    }

    /// The person's answer to the question.
    public func answer(_ worked: Bool, note: String? = nil) async {
        guard case .asking = phase else { return }
        await finishStep(answer: worked, note: note)
    }

    /// Stops here: puts back what the current step changed, records the rest as not run, tidies
    /// up and writes the report.
    public func stop() async {
        switch phase {
        case .finished, .running: return
        case .asking: await finishStep(answer: nil, note: "Stopped before answering")
        // Nothing ran yet: no report.
        case .intro: phase = .finished; return
        case .ready: break
        }
        guard phase != .finished else { return }
        await wrapUp()
    }

    private func finishStep(answer: Bool?, note: String?) async {
        guard let (step, trial, snapshot) = pending else { return }
        pending = nil
        phase = .running("Putting things back")
        var restored: [LiveCheckRestoreNote] = []
        let made = trial.made.filter { mac.fileSize($0) != nil }
        if !made.isEmpty {
            let gone = mac.trash(made)
            restored.append(LiveCheckRestoreNote(ok: gone == made.count, gone == made.count
                ? "Moved \(made.count == 1 ? "the file" : "the \(made.count) files") it made to the Trash"
                : "Could not move \(made.map(\.lastPathComponent).joined(separator: ", ")) to the Trash"))
        }
        restored += await LiveCheckRestorer.restore(snapshot, on: mac)
        mac.returnToCheck()
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        records.append(LiveCheckRecord(group: step.group, title: step.title,
                                       verdict: LiveCheckRecord.verdict(trial, answer: answer),
                                       observed: trial.observed, restored: restored,
                                       note: trimmed?.isEmpty == false ? trimmed : nil))
        await advance()
    }

    private func advance() async {
        index += 1
        if index < steps.count {
            currentUnavailable = current.flatMap { $0.unavailable(mac) }
            phase = .ready
            writeReport(finished: false)
        } else {
            await wrapUp()
        }
    }

    private func wrapUp() async {
        phase = .running("Closing the test windows")
        await mac.wrapUp()
        mac.returnToCheck()
        phase = .finished
        writeReport(finished: true)
    }

    private func writeReport(finished: Bool) {
        let notRun = finished ? steps.dropFirst(records.count).map(\.title) : []
        let text = LiveCheckReport.markdown(header, records: records, notRun: notRun, finished: finished)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if reportURL == nil {
                let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                reportURL = folder.appendingPathComponent(LiveCheckReport.fileName(date: header.started, existing: existing))
            }
            try Data(text.utf8).write(to: reportURL!, options: .atomic)
            reportError = nil
        } catch {
            reportError = "Could not write the report: \(error.localizedDescription)"
        }
    }
}
