import AppKit
import GlasspadKit
import GlasspadMacCore
import SwiftUI

/// The guided live check: started with `--live-check` (scripts/live-check.sh), never from the
/// menus. Glasspad then does not listen for the phone; it opens this window, walks through every
/// Mac feature on the real Mac, puts each one back, and quits when it is done.
@MainActor
final class LiveCheckWindow: NSObject, NSWindowDelegate {
    static let launchArgument = "--live-check"
    static let disruptiveArgument = "--include-disruptive"

    static var requested: Bool { CommandLine.arguments.contains(launchArgument) }

    private var window: NSWindow?
    private var runner: LiveCheckRunner?

    func show(router: ModeRouter) {
        let mac = LiveCheckLiveMac(router: router) { [weak self] in self?.bringToFront() }
        let header = LiveCheckReport.Header(
            started: Date(), mac: Host.current().localizedName ?? "Mac",
            system: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            app: AppInfoText.version, displays: NSScreen.screens.count,
            disruptive: CommandLine.arguments.contains(Self.disruptiveArgument))
        let runner = LiveCheckRunner(steps: LiveCheckSteps.all(), mac: mac, includeDisruptive: header.disruptive, header: header)
        self.runner = runner
        let host = NSHostingController(rootView: LiveCheckView(runner: runner, accessibility: AXIsProcessTrusted(),
                                                               done: { NSApp.terminate(nil) }))
        let w = NSWindow(contentViewController: host)
        w.title = "Live Check"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        // Top right, out of the way of the test windows in the middle of the screen.
        if let v = NSScreen.main?.visibleFrame {
            w.setFrameTopLeftPoint(NSPoint(x: v.maxX - w.frame.width - 24, y: v.maxY - 24))
        } else {
            w.center()
        }
        window = w
        bringToFront()
    }

    func bringToFront() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Not while a step runs: it would leave something half done.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if case .running = runner?.phase { return false }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let runner else { return NSApp.terminate(nil) }
        Task {
            await runner.stop()
            NSApp.terminate(nil)
        }
    }
}

// MARK: - View

struct LiveCheckView: View {
    @ObservedObject var runner: LiveCheckRunner
    let accessibility: Bool
    let done: () -> Void
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: 480)
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Live Check")
                    .font(.title2.weight(.semibold))
                Spacer()
                if showsProgress {
                    Text("\(min(runner.index + 1, runner.steps.count)) of \(runner.steps.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if showsProgress {
                ProgressView(value: Double(runner.index), total: Double(max(1, runner.steps.count)))
                    .progressViewStyle(.linear)
            }
        }
    }

    private var showsProgress: Bool {
        switch runner.phase {
        case .intro, .finished: false
        default: true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch runner.phase {
        case .intro: intro
        case .ready: ready
        case .running(let status): running(status)
        case .asking(let question, let observed): asking(question, observed)
        case .finished: finished
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Glasspad tries each Mac feature for real, one at a time, through the same code your iPhone uses. After each one it puts your Mac back the way it was.")
            Text("Window tests use two TextEdit windows that Glasspad opens and closes itself. Your own windows are never moved.")
                .foregroundStyle(.secondary)
            Text(runner.includesDisruptive
                 ? "Lock Screen, Sleep, Empty Trash and Eject All are included. You can skip each one."
                 : "Lock Screen, Sleep, Empty Trash and Eject All are left out.")
                .foregroundStyle(.secondary)
            if !accessibility {
                Label("Glasspad does not have Accessibility, so window and Control Center tests will fail. Allow it in System Settings > Privacy & Security > Accessibility, then start again.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var ready: some View {
        if let step = runner.current {
            VStack(alignment: .leading, spacing: 8) {
                Text(step.group.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(step.title)
                    .font(.title3.weight(.semibold))
                Text(step.summary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = runner.currentUnavailable {
                    Label(reason, systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                } else if let getReady = step.getReady {
                    Label(getReady, systemImage: "hand.point.right")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let last = runner.last {
                    LastResult(record: last)
                }
            }
        }
    }

    private func running(_ status: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let step = runner.current {
                Text(step.title)
                    .font(.title3.weight(.semibold))
            }
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(status)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func asking(_ question: String, _ observed: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let step = runner.current {
                Text(step.title)
                    .font(.title3.weight(.semibold))
            }
            Text(question)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if !observed.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(observed.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Note (optional)", text: $note)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var finished: some View {
        let passed = runner.records.filter { $0.verdict == .pass }.count
        let failed = runner.records.filter { $0.verdict == .fail }
        let skipped = runner.records.filter { $0.verdict == .skipped }.count
        let unrestored = runner.records.flatMap(\.restored).filter { !$0.ok }
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(passed) passed, \(failed.count) failed, \(skipped) skipped")
                .font(.title3.weight(.semibold))
            if !failed.isEmpty {
                Text("Failed: \(failed.map(\.title).joined(separator: ", "))")
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(unrestored.enumerated()), id: \.offset) { _, n in
                Label(n.text, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = runner.reportURL {
                Text("The report is in \((url.path as NSString).abbreviatingWithTildeInPath).")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = runner.reportError {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            switch runner.phase {
            case .intro:
                Button("Quit", action: done)
                Spacer()
                Button("Start") { runner.start() }
                    .keyboardShortcut(.defaultAction)
            case .ready:
                Button("Stop") { Task { await runner.stop() } }
                Spacer()
                if runner.currentUnavailable == nil {
                    Button("Skip") { Task { await runner.skip() } }
                    Button("Run") { Task { await runner.run() } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Skip") { Task { await runner.skip() } }
                        .keyboardShortcut(.defaultAction)
                }
            case .running:
                Spacer()
            case .asking:
                Button("Stop") { Task { await runner.stop() } }
                Spacer()
                Button("No") { answer(false) }
                Button("Yes") { answer(true) }
                    .keyboardShortcut(.defaultAction)
            case .finished:
                if let url = runner.reportURL {
                    Button("Show Report") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }

    private func answer(_ worked: Bool) {
        let text = note
        note = ""
        Task { await runner.answer(worked, note: text) }
    }
}

/// The step before this one, in a single line.
private struct LastResult: View {
    let record: LiveCheckRecord

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text("\(record.title): \(word)")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var symbol: String {
        switch record.verdict {
        case .pass: "checkmark.circle.fill"
        case .fail: "xmark.circle.fill"
        case .skipped: "minus.circle.fill"
        }
    }

    private var color: Color {
        switch record.verdict {
        case .pass: .green
        case .fail: .red
        case .skipped: .secondary
        }
    }

    private var word: String {
        switch record.verdict {
        case .pass: "passed"
        case .fail: "failed"
        case .skipped: "skipped"
        }
    }
}
