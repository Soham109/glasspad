import Foundation
import GlasspadKit
import GlasspadMacros

// MARK: - Wire conversions (GlasspadMacros -> GlasspadKit)

public extension GlasspadKit.MacroSummary {
    init(_ s: GlasspadMacros.MacroSummary) {
        self.init(id: s.id, name: s.name, symbol: s.symbol, color: s.color, stepCount: s.stepCount, usesScripts: s.usesScripts)
    }
}

public extension GlasspadKit.ActiveProfileInfo {
    init(_ p: GlasspadMacros.ActiveProfileInfo) {
        self.init(profileID: p.profileID, name: p.name, symbol: p.symbol, bundleID: p.bundleID,
                  macros: p.macros.map(GlasspadKit.MacroSummary.init))
    }
}

public extension GlasspadKit.MacroProgress {
    init(_ p: GlasspadMacros.MacroProgress) {
        self.init(macroID: p.macroID, completedSteps: p.completedSteps, totalSteps: p.totalSteps,
                  currentPath: p.currentPath, currentSummary: p.currentSummary)
    }
}

public extension RunOutcome {
    init(_ o: PlaybackResult.Outcome) {
        switch o {
        case .completed: self = .completed
        case .cancelled: self = .cancelled
        case .interruptedByUser: self = .interruptedByUser
        case .failed: self = .failed
        }
    }
}

extension PlaybackResult {
    /// The `runFinished` message for the phone.
    func message(for id: UUID) -> MacroMessage {
        var text: String?
        if case .failed(let e) = outcome { text = e.description }
        return .runFinished(macroID: id, outcome: RunOutcome(outcome), message: text, outputs: outputs.map(\.text))
    }
}

// MARK: - Coordinator

/// Glues `MacroEngine` to the phone link and to the Settings window: answers `MacroMessage`s,
/// pushes the active profile on every frontmost-app change, relays progress, and turns
/// recordings into saved macros. Main actor, like the engine.
@MainActor
public final class MacroCoordinator: ObservableObject {
    @Published public private(set) var macros: [Macro] = []
    @Published public private(set) var profiles: [ContextProfile] = []
    @Published public private(set) var activeProfile: GlasspadKit.ActiveProfileInfo
    @Published public private(set) var isRecording = false
    @Published public private(set) var runningMacroID: UUID?
    @Published public private(set) var lastProgress: GlasspadKit.MacroProgress?
    /// Shown in Settings (and sent to the phone where it applies).
    @Published public private(set) var lastError: String?
    @Published public private(set) var loadFailures: [MacroStore.LoadFailure] = []
    /// Set when a recording was saved; Settings selects it so the user can rename it.
    @Published public private(set) var lastRecordedID: UUID?

    public let engine: MacroEngine
    /// Mac -> phone. The controller points this at the server.
    public var send: (MacroMessage) -> Void = { _ in }
    private var started = false

    public init(engine: MacroEngine) {
        self.engine = engine
        self.activeProfile = GlasspadKit.ActiveProfileInfo(engine.activeProfileInfo)
    }

    /// The app's coordinator: real stores, the Glasspad macro environment and Carbon hotkeys.
    public static func live(poster: EventPoster) -> MacroCoordinator {
        let engine = MacroEngine(player: MacroPlayer(environment: .glasspad(poster: poster)), hotkeys: CarbonHotkeyCenter())
        return MacroCoordinator(engine: engine)
    }

    public func start(seedStarters: Bool = true) {
        guard !started else { return }
        engine.onActiveProfileChanged = { [weak self] info in self?.profileChanged(info) }
        engine.onProgress = { [weak self] p, _ in
            let progress = GlasspadKit.MacroProgress(p)
            self?.lastProgress = progress
            self?.send(.progress(progress))
        }
        engine.onRunFinished = { [weak self] id, trigger, result in
            // Phone-started runs are reported by `run(_:trigger:)` itself (it also covers runs
            // the engine refuses before starting); report the rest so the phone sees them too.
            switch trigger {
            case .hotkey, .mac: self?.send(result.message(for: id))
            case .deck, .gesture: break
            }
        }
        engine.onRecordingStoppedByHotkey = { [weak self] result in self?.finishRecording(result) }
        do {
            try engine.start(seedStarters: seedStarters)
            started = true
        } catch {
            lastError = "Could not load macros: \(Self.text(error))"
        }
        refresh()
    }

    public func stop() {
        if engine.isRecording { _ = try? engine.stopRecording() }
        engine.stop()
        started = false
        refresh()
    }

    /// A phone just connected (or replaced another): give it the buttons and recording state.
    public func sessionStarted() {
        send(.activeProfileChanged(activeProfile))
        if isRecording { send(.recordingState(isRecording: true)) }
    }

    // MARK: Phone messages

    public func handle(_ message: MacroMessage) {
        switch message {
        case .listMacros:
            send(.macroList(active: activeProfile, all: engine.macros.map { GlasspadKit.MacroSummary(GlasspadMacros.MacroSummary($0)) }))
        case .run(let id):
            Task { await run(id, trigger: .deck) }
        case .gesture(let name):
            guard let m = TriggerRouter(macros: engine.macros).macro(forGesture: name, activeProfile: engine.activeProfile) else {
                return
            }
            Task { await run(m.id, trigger: .gesture(name)) }
        case .cancelRun:
            engine.cancelRun()
        case .recordStart(let windowRelative, let keepTiming):
            startRecording(windowRelative: windowRelative, keepTiming: keepTiming)
        case .recordStop:
            stopRecording(fromMacMenu: false)
        case .macroList, .activeProfileChanged, .progress, .runFinished, .recordingState, .recordingFinished,
             .recordingFailed:
            break   // Mac -> phone only
        }
    }

    /// Runs a macro and reports the outcome to the phone. Settings uses `.mac`.
    @discardableResult
    public func run(_ id: UUID, trigger: MacroTrigger = .mac) async -> PlaybackResult {
        runningMacroID = id
        let result = await engine.run(id, trigger: trigger)
        runningMacroID = engine.runningMacroID
        if case .failed(let e) = result.outcome { lastError = e.description }
        switch trigger {
        case .deck, .gesture: send(result.message(for: id))
        case .hotkey, .mac:
            // The engine reported a real run through onRunFinished; only its refusals are left.
            switch result.outcome {
            case .failed(.busy), .failed(.macroNotFound): send(result.message(for: id))
            default: break
            }
        }
        return result
    }

    public func cancelRun() { engine.cancelRun() }

    // MARK: Recording

    /// Starts recording the Mac's keyboard and mouse. Errors go to `lastError` and the phone.
    public func startRecording(windowRelative: Bool = false, keepTiming: Bool = true) {
        do {
            try engine.startRecording(options: RecordingOptions(positions: windowRelative ? .frontWindow : .screen,
                                                                keepTiming: keepTiming))
            lastError = nil
            isRecording = true
            send(.recordingState(isRecording: true))
        } catch {
            isRecording = engine.isRecording
            let text = Self.text(error)
            lastError = text
            send(.recordingFailed(message: text))
            send(.recordingState(isRecording: isRecording))
        }
    }

    /// Stops recording and saves the result as a new macro. `fromMacMenu` drops the click on
    /// the Mac control that stopped it. Returns the saved macro.
    @discardableResult
    public func stopRecording(fromMacMenu: Bool) -> Macro? {
        do {
            return finishRecording(try engine.stopRecording(fromMacMenu: fromMacMenu))
        } catch {
            isRecording = engine.isRecording
            let text = Self.text(error)
            lastError = text
            send(.recordingFailed(message: text))
            send(.recordingState(isRecording: isRecording))
            return nil
        }
    }

    @discardableResult
    private func finishRecording(_ result: RecordingResult) -> Macro? {
        isRecording = false
        defer { send(.recordingState(isRecording: false)) }
        guard !result.steps.isEmpty else {
            let text = "Nothing was recorded."
            lastError = text
            send(.recordingFailed(message: text))
            return nil
        }
        let draft = MacroEngine.draft(from: result, name: nextRecordingName())
        do {
            try engine.save(draft)
        } catch {
            let text = "Could not save the recording: \(Self.text(error))"
            lastError = text
            send(.recordingFailed(message: text))
            return nil
        }
        lastError = nil
        lastRecordedID = draft.id
        refresh()
        send(.recordingFinished(macro: GlasspadKit.MacroSummary(GlasspadMacros.MacroSummary(draft)), droppedSecureKeys: result.droppedSecureKeyEvents))
        return draft
    }

    /// "Recording 1", "Recording 2", ... the lowest number not in use.
    func nextRecordingName() -> String {
        let names = Set(engine.macros.map(\.name))
        var n = 1
        while names.contains("Recording \(n)") { n += 1 }
        return "Recording \(n)"
    }

    // MARK: Editing (Settings)

    public func save(_ macro: Macro) throws {
        try engine.save(macro)
        refresh()
    }

    public func delete(_ id: UUID) throws {
        try engine.delete(id: id)
        refresh()
    }

    public func save(profiles: [ContextProfile]) throws {
        try engine.save(profiles: profiles)
        refresh()
    }

    public func restoreStarters() throws {
        try engine.restoreStarters()
        refresh()
    }

    public func macro(_ id: UUID) -> Macro? { engine.macro(id: id) }

    public var triggerConflicts: [TriggerConflict] { engine.triggerConflicts }

    public func clearError() { lastError = nil }

    // MARK: Private

    private func profileChanged(_ info: GlasspadMacros.ActiveProfileInfo) {
        let kit = GlasspadKit.ActiveProfileInfo(info)
        activeProfile = kit
        send(.activeProfileChanged(kit))
    }

    private func refresh() {
        macros = engine.macros
        profiles = engine.profiles
        loadFailures = engine.loadFailures
        isRecording = engine.isRecording
        activeProfile = GlasspadKit.ActiveProfileInfo(engine.activeProfileInfo)
    }

    static func text(_ error: Error) -> String {
        (error as? MacroError)?.description ?? error.localizedDescription
    }
}
