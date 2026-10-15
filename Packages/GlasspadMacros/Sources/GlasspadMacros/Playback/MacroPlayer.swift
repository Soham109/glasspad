import Foundation
import CoreGraphics

/// Everything the player needs from the outside world. `live()` gives the
/// real Mac implementations; tests pass fakes.
public struct MacroEnvironment: Sendable {
    public var output: any MacroEventOutput
    public var windows: any FrontmostWindowProviding
    public var apps: any AppLaunching
    public var shortcuts: any ShortcutsRunning
    public var scripts: any ScriptRunning
    public var clipboard: any ClipboardWriting
    public var notifier: any Notifying
    public var clock: any MacroClock
    public var inputMonitor: (any UserInputMonitoring)?

    public init(output: any MacroEventOutput, windows: any FrontmostWindowProviding, apps: any AppLaunching,
                shortcuts: any ShortcutsRunning, scripts: any ScriptRunning, clipboard: any ClipboardWriting,
                notifier: any Notifying, clock: any MacroClock, inputMonitor: (any UserInputMonitoring)?) {
        self.output = output
        self.windows = windows
        self.apps = apps
        self.shortcuts = shortcuts
        self.scripts = scripts
        self.clipboard = clipboard
        self.notifier = notifier
        self.clock = clock
        self.inputMonitor = inputMonitor
    }

    public static func live() -> MacroEnvironment {
        MacroEnvironment(
            output: CGEventOutput(),
            windows: AXWindowProvider(),
            apps: WorkspaceAppLauncher(),
            shortcuts: ShortcutsCLI(),
            scripts: SystemScriptRunner(),
            clipboard: PasteboardClipboard(),
            notifier: SystemNotifier(),
            clock: ContinuousMacroClock(),
            inputMonitor: EventTapUserInputMonitor())
    }
}

/// A step after its run-time values are known: window-relative points turned
/// into screen points, waits scaled by speed, paths expanded to URLs.
public enum ResolvedAction: Equatable, Sendable {
    case press(KeyCombo)
    case type(String)
    case moveMouse(to: CGPoint)
    case click(MouseButton, at: CGPoint, count: Int, modifiers: KeyModifiers)
    case drag(MouseButton, from: CGPoint, to: CGPoint, durationMs: Int)
    case scroll(dx: Int, dy: Int)
    case wait(ms: Double)
    case waitForApp(bundleID: String, timeoutMs: Int)
    case openApp(bundleID: String)
    case open(URL)
    case runShortcut(nameOrID: String, input: String?)
    case runAppleScript(source: String)
    case runShell(command: String, timeoutMs: Int)
    case setClipboard(String)
    case notify(title: String, body: String)
}

public struct PlannedAction: Equatable, Sendable {
    /// Index path of the step in the macro; repeat blocks add a level.
    public var path: [Int]
    public var action: ResolvedAction
}

public struct PlaybackOptions: Sendable {
    /// 2 plays twice as fast (waits are halved). Clamped to 0.05...20.
    public var speed: Double
    /// Stop as soon as the real mouse or keyboard is used.
    public var stopOnUserInput: Bool

    public init(speed: Double = 1, stopOnUserInput: Bool = true) {
        self.speed = speed
        self.stopOnUserInput = stopOnUserInput
    }

    var clampedSpeed: Double { min(max(speed, 0.05), 20) }
}

public struct MacroProgress: Equatable, Codable, Sendable {
    public var macroID: UUID
    public var completedSteps: Int
    public var totalSteps: Int
    /// Index path of the step about to run, empty when finished.
    public var currentPath: [Int]
    public var currentSummary: String

    public var fraction: Double { totalSteps == 0 ? 1 : Double(completedSteps) / Double(totalSteps) }
}

public struct StepOutput: Equatable, Codable, Sendable {
    public var path: [Int]
    public var text: String
}

public struct PlaybackResult: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case completed
        case cancelled
        /// The real mouse or keyboard was used and `stopOnUserInput` was on.
        case interruptedByUser
        case failed(MacroError)
    }

    public var outcome: Outcome
    public var stepsCompleted: Int
    public var totalSteps: Int
    /// Path of the step that failed or was running when stopped.
    public var stoppedAt: [Int]?
    /// Text produced by shortcuts, AppleScript and shell steps.
    public var outputs: [StepOutput]
    /// False when `stopOnUserInput` was asked for but the monitor could not start.
    public var userInputGuardActive: Bool
}

/// Plays macros. One player can run one macro at a time per call; the engine
/// makes sure only one macro plays at once.
public final class MacroPlayer: Sendable {
    public static let maxRepeatCount = 10_000
    public static let maxExpandedSteps = 100_000
    public static let maxWaitMs = 3_600_000
    static let appPollIntervalMs = 100.0

    public let environment: MacroEnvironment

    public init(environment: MacroEnvironment) {
        self.environment = environment
    }

    // MARK: Validation

    /// Checks the whole macro before anything runs, so a bad step near the end
    /// never leaves a half-played macro behind.
    public static func validate(_ macro: Macro) throws -> Int {
        if macro.needsScriptPermission && !macro.allowScripts { throw MacroError.scriptsNotAllowed }
        return try countAndValidate(macro.steps, path: [])
    }

    private static func countAndValidate(_ steps: [MacroStep], path: [Int]) throws -> Int {
        var total = 0
        for (i, step) in steps.enumerated() {
            let p = path + [i]
            func bad(_ reason: String) -> MacroError { .invalidStep(path: p, reason: reason) }
            switch step {
            case .repeatBlock(let n, let inner):
                guard (1...maxRepeatCount).contains(n) else { throw bad("Repeat count must be 1 to \(maxRepeatCount).") }
                let innerCount = try countAndValidate(inner, path: p)
                total += n * innerCount
            case .wait(let ms):
                guard (0...maxWaitMs).contains(ms) else { throw bad("Wait must be 0 to \(maxWaitMs) ms.") }
                total += 1
            case .waitForApp(let id, let t):
                guard !id.isEmpty else { throw bad("Missing bundle id.") }
                guard (1...maxWaitMs).contains(t) else { throw bad("Timeout must be 1 to \(maxWaitMs) ms.") }
                total += 1
            case .openApp(let id):
                guard !id.isEmpty else { throw bad("Missing bundle id.") }
                total += 1
            case .click(_, _, let n, _):
                guard (1...3).contains(n) else { throw bad("Click count must be 1, 2 or 3.") }
                total += 1
            case .drag(_, _, _, let d):
                guard (0...60_000).contains(d) else { throw bad("Drag duration must be 0 to 60000 ms.") }
                total += 1
            case .runShell(let cmd, let t):
                guard !cmd.trimmingCharacters(in: .whitespaces).isEmpty else { throw bad("Empty command.") }
                guard (1...maxWaitMs).contains(t) else { throw bad("Timeout must be 1 to \(maxWaitMs) ms.") }
                total += 1
            case .runShortcut(let name, _):
                guard !name.isEmpty else { throw bad("Missing shortcut name.") }
                total += 1
            case .typeText(let t):
                guard !t.isEmpty else { throw bad("Nothing to type.") }
                total += 1
            default:
                total += 1
            }
            if total > maxExpandedSteps { throw bad("The macro expands to more than \(maxExpandedSteps) steps.") }
        }
        return total
    }

    // MARK: Dry run

    /// Resolves every step (including window-relative points, against the
    /// window that is frontmost now) and returns what would happen, without
    /// posting, opening, running or waiting for anything.
    public func dryRun(_ macro: Macro, options: PlaybackOptions = .init()) throws -> [PlannedAction] {
        _ = try Self.validate(macro)
        var plan: [PlannedAction] = []
        try Self.expand(macro.steps, path: []) { step, path in
            plan.append(PlannedAction(path: path, action: try resolve(step, path: path, speed: options.clampedSpeed)))
        }
        return plan
    }

    private static func expand(_ steps: [MacroStep], path: [Int],
                               _ visit: (MacroStep, [Int]) throws -> Void) throws {
        for (i, step) in steps.enumerated() {
            if case .repeatBlock(let n, let inner) = step {
                for _ in 0..<n { try expand(inner, path: path + [i], visit) }
            } else {
                try visit(step, path + [i])
            }
        }
    }

    private static func expandAsync(_ steps: [MacroStep], path: [Int],
                                    _ visit: (MacroStep, [Int]) async throws -> Void) async throws {
        for (i, step) in steps.enumerated() {
            if case .repeatBlock(let n, let inner) = step {
                for _ in 0..<n { try await expandAsync(inner, path: path + [i], visit) }
            } else {
                try await visit(step, path + [i])
            }
        }
    }

    func resolve(_ step: MacroStep, path: [Int], speed: Double) throws -> ResolvedAction {
        func point(_ p: MacroPoint) throws -> CGPoint {
            try p.resolve(windowFrame: p.isWindowRelative ? environment.windows.frontmostWindowFrame() : nil)
        }
        switch step {
        case .keystroke(let k): return .press(k)
        case .typeText(let t): return .type(t)
        case .click(let b, let p, let n, let m): return .click(b, at: try point(p), count: n, modifiers: m)
        case .moveMouse(let p): return .moveMouse(to: try point(p))
        case .drag(let b, let from, let to, let d):
            // Both ends are resolved against the same window frame, read once.
            let frame = (from.isWindowRelative || to.isWindowRelative) ? environment.windows.frontmostWindowFrame() : nil
            return .drag(b, from: try from.resolve(windowFrame: frame), to: try to.resolve(windowFrame: frame),
                         durationMs: Int((Double(d) / speed).rounded()))
        case .scroll(let dx, let dy): return .scroll(dx: dx, dy: dy)
        case .wait(let ms): return .wait(ms: Double(ms) / speed)
        case .waitForApp(let id, let t): return .waitForApp(bundleID: id, timeoutMs: t)
        case .openApp(let id): return .openApp(bundleID: id)
        case .openURL(let s):
            guard let url = URL(string: s.trimmingCharacters(in: .whitespaces)), let scheme = url.scheme,
                  !scheme.isEmpty else { throw MacroError.invalidURL(s) }
            return .open(url)
        case .openFile(let path):
            let expanded = (path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else { throw MacroError.fileNotFound(path) }
            return .open(URL(fileURLWithPath: expanded))
        case .runShortcut(let n, let input): return .runShortcut(nameOrID: n, input: input)
        case .runAppleScript(let s): return .runAppleScript(source: s)
        case .runShell(let c, let t): return .runShell(command: c, timeoutMs: t)
        case .setClipboard(let t): return .setClipboard(t)
        case .notify(let t, let b): return .notify(title: t, body: b)
        case .repeatBlock:
            preconditionFailure("repeat blocks are expanded before resolving")
        }
    }

    // MARK: Run

    /// Plays a macro. Cancel the calling task to stop it at any point.
    /// Never throws: every way it can end is in the result's `outcome`.
    public func run(_ macro: Macro, options: PlaybackOptions = .init(),
                    progress: @escaping @Sendable (MacroProgress) -> Void = { _ in }) async -> PlaybackResult {
        let total: Int
        do {
            total = try Self.validate(macro)
        } catch {
            return PlaybackResult(outcome: .failed(error as? MacroError ?? .outputFailed("\(error)")),
                                  stepsCompleted: 0, totalSteps: 0, stoppedAt: nil, outputs: [],
                                  userInputGuardActive: false)
        }

        let state = LockedBox(RunState())
        let workBox = LockedBox<Task<Void, Error>?>(nil)
        let speed = options.clampedSpeed

        // The guard starts before the first step so nothing runs unguarded.
        var guardActive = false
        if options.stopOnUserInput, let monitor = environment.inputMonitor {
            guardActive = monitor.start {
                state.update { $0.userInterrupted = true }
                workBox.get()?.cancel()
            }
        }

        let work = Task<Void, Error> {
            try await Self.expandAsync(macro.steps, path: []) { step, path in
                try Task.checkCancellation()
                let done = state.update { s -> Int in s.current = path; return s.completed }
                progress(MacroProgress(macroID: macro.id, completedSteps: done, totalSteps: total,
                                       currentPath: path, currentSummary: step.summary))
                let action = try self.resolve(step, path: path, speed: speed)
                if let text = try await self.perform(action), !text.isEmpty {
                    state.update { $0.outputs.append(StepOutput(path: path, text: text)) }
                }
                try Task.checkCancellation()
                state.update { $0.completed += 1 }
            }
        }
        workBox.set(work)
        if state.get().userInterrupted { work.cancel() }

        let outcome: PlaybackResult.Outcome
        do {
            try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            outcome = .completed
        } catch is CancellationError {
            outcome = state.get().userInterrupted ? .interruptedByUser : .cancelled
        } catch let e as MacroError {
            outcome = .failed(e)
        } catch {
            outcome = .failed(.outputFailed(String(describing: error)))
        }
        if guardActive { environment.inputMonitor?.stop() }

        let final = state.get()
        if outcome == .completed {
            progress(MacroProgress(macroID: macro.id, completedSteps: total, totalSteps: total,
                                   currentPath: [], currentSummary: "Done"))
        }
        return PlaybackResult(outcome: outcome, stepsCompleted: final.completed, totalSteps: total,
                              stoppedAt: outcome == .completed ? nil : final.current,
                              outputs: final.outputs, userInputGuardActive: guardActive)
    }

    private struct RunState {
        var completed = 0
        var current: [Int] = []
        var outputs: [StepOutput] = []
        var userInterrupted = false
    }

    /// Performs one resolved action. Returns any text output.
    func perform(_ action: ResolvedAction) async throws -> String? {
        let env = environment
        switch action {
        case .press(let k): try await env.output.press(k)
        case .type(let t): try await env.output.type(t)
        case .moveMouse(let p): try await env.output.moveMouse(to: p)
        case .click(let b, let p, let n, let m): try await env.output.click(b, at: p, count: n, modifiers: m)
        case .drag(let b, let from, let to, let d): try await env.output.drag(b, from: from, to: to, durationMs: d)
        case .scroll(let dx, let dy): try await env.output.scroll(dx: dx, dy: dy)
        case .wait(let ms): try await env.clock.sleep(ms: ms)
        case .waitForApp(let id, let timeout):
            let deadline = env.clock.nowMs() + Double(timeout)
            while env.windows.frontmostBundleID() != id {
                guard env.clock.nowMs() < deadline else { throw MacroError.timedOutWaitingForApp(bundleID: id) }
                try await env.clock.sleep(ms: Self.appPollIntervalMs)
            }
        case .openApp(let id): try await env.apps.openApp(bundleID: id)
        case .open(let url): try await env.apps.open(url: url)
        case .runShortcut(let n, let input): return try await env.shortcuts.run(n, input: input)
        case .runAppleScript(let s): return try await env.scripts.runAppleScript(s)
        case .runShell(let c, let t): return try await env.scripts.runShell(c, timeoutMs: t)
        case .setClipboard(let t): env.clipboard.setString(t)
        case .notify(let t, let b): try await env.notifier.notify(title: t, body: b)
        }
        return nil
    }
}
