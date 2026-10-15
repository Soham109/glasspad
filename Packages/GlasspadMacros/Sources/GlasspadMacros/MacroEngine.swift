import Foundation

/// What the phone needs to draw one macro button.
public struct MacroSummary: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var color: String
    public var stepCount: Int
    public var usesScripts: Bool

    public init(_ m: Macro) {
        id = m.id
        name = m.name
        symbol = m.symbol
        color = m.color
        stepCount = m.steps.count
        usesScripts = m.needsScriptPermission
    }
}

/// Sent to the phone whenever the frontmost app changes the profile.
public struct ActiveProfileInfo: Equatable, Codable, Sendable {
    public var profileID: UUID?
    public var name: String
    public var symbol: String
    public var bundleID: String?
    public var macros: [MacroSummary]
}

/// Ties the store, player, recorder, profiles and triggers together. This is
/// the one object the Mac app owns; it maps phone messages onto its methods.
@MainActor
public final class MacroEngine {
    public private(set) var macros: [Macro] = []
    public private(set) var profiles: [ContextProfile] = []
    public private(set) var loadFailures: [MacroStore.LoadFailure] = []
    public private(set) var activeProfile: ContextProfile?
    public private(set) var runningMacroID: UUID?
    public private(set) var unregisteredHotkeys: [KeyCombo] = []

    public var playbackOptions = PlaybackOptions()

    public var onProgress: ((MacroProgress, MacroTrigger) -> Void)?
    public var onRunFinished: ((UUID, MacroTrigger, PlaybackResult) -> Void)?
    public var onActiveProfileChanged: ((ActiveProfileInfo) -> Void)?
    /// Called when the user ends a recording with the stop hotkey.
    public var onRecordingStoppedByHotkey: ((RecordingResult) -> Void)?

    private let store: MacroStore
    private let profileStore: ProfileStore
    private let player: MacroPlayer
    private let recorder: MacroRecorder
    private let switcher: ProfileSwitcher
    private let hotkeys: (any HotkeyRegistering)?
    private var runTask: Task<PlaybackResult, Never>?

    public init(store: MacroStore = MacroStore(), profileStore: ProfileStore = ProfileStore(),
                player: MacroPlayer = MacroPlayer(environment: .live()),
                recorder: MacroRecorder = MacroRecorder(),
                switcher: ProfileSwitcher = ProfileSwitcher(),
                hotkeys: (any HotkeyRegistering)? = nil) {
        self.store = store
        self.profileStore = profileStore
        self.player = player
        self.recorder = recorder
        self.switcher = switcher
        self.hotkeys = hotkeys
    }

    /// Convenience for the app: everything real, with Carbon hotkeys.
    public static func live() -> MacroEngine {
        MacroEngine(hotkeys: CarbonHotkeyCenter())
    }

    // MARK: Lifecycle

    /// Seeds starters on first launch, loads everything, registers hotkeys
    /// and starts following the frontmost app.
    public func start(seedStarters: Bool = true) throws {
        if seedStarters { try StarterSeeder.seedIfNeeded(macros: store, profiles: profileStore) }
        reloadMacros()
        profiles = try profileStore.load() ?? []
        registerHotkeys()
        switcher.update(profiles: profiles)
        switcher.start { [weak self] profile in
            Self.onMain { self?.profileDidChange(profile) }
        }
    }

    public func stop() {
        switcher.stop()
        hotkeys?.removeAll()
        cancelRun()
    }

    private nonisolated static func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async { body() }
        }
    }

    private func reloadMacros() {
        let loaded = store.loadAll()
        macros = loaded.macros.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        loadFailures = loaded.failures
    }

    private func registerHotkeys() {
        guard let hotkeys else { return }
        let bindings = TriggerRouter(macros: macros).hotkeyBindings
        unregisteredHotkeys = hotkeys.setHotkeys(bindings.map(\.combo)) { [weak self] combo in
            guard let self, let m = TriggerRouter(macros: self.macros).macro(forHotkey: combo) else { return }
            Task { _ = await self.run(m.id, trigger: .hotkey) }
        }
    }

    private func profileDidChange(_ profile: ContextProfile?) {
        activeProfile = profile
        onActiveProfileChanged?(activeProfileInfo)
    }

    public var activeProfileInfo: ActiveProfileInfo {
        ActiveProfileInfo(profileID: activeProfile?.id, name: activeProfile?.name ?? "All Macros",
                          symbol: activeProfile?.symbol ?? "square.grid.2x2",
                          bundleID: switcher.frontmostBundleID,
                          macros: summaries(for: activeProfile))
    }

    /// Buttons for a profile in its order; with no profile, every macro.
    /// Ids that no longer exist are skipped.
    public func summaries(for profile: ContextProfile?) -> [MacroSummary] {
        guard let profile else { return macros.map(MacroSummary.init) }
        let byID = Dictionary(macros.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return profile.macroIDs.compactMap { byID[$0].map(MacroSummary.init) }
    }

    public func macro(id: UUID) -> Macro? { macros.first { $0.id == id } }

    // MARK: Editing

    public func save(_ macro: Macro) throws {
        try store.save(macro)
        reloadMacros()
        registerHotkeys()
        profileDidChange(activeProfile.flatMap { a in profiles.first { $0.id == a.id } })
    }

    /// Deletes a macro and removes its button from every profile.
    public func delete(id: UUID) throws {
        try store.delete(id: id)
        reloadMacros()
        var changed = profiles
        for i in changed.indices { changed[i].macroIDs.removeAll { $0 == id } }
        try save(profiles: changed)
        registerHotkeys()
    }

    public func save(profiles newProfiles: [ContextProfile]) throws {
        try profileStore.save(newProfiles)
        profiles = newProfiles
        switcher.update(profiles: newProfiles)
        profileDidChange(switcher.activeProfile)
    }

    public func restoreStarters() throws {
        try StarterSeeder.restoreStarters(macros: store, profiles: profileStore)
        reloadMacros()
        try save(profiles: try profileStore.load() ?? [])
        registerHotkeys()
    }

    public var triggerConflicts: [TriggerConflict] { TriggerRouter(macros: macros).conflicts }

    // MARK: Running

    /// Runs a macro. Only one macro plays at a time; a second request while
    /// one is playing fails with `.busy` rather than interleaving input.
    @discardableResult
    public func run(_ id: UUID, trigger: MacroTrigger, options: PlaybackOptions? = nil) async -> PlaybackResult {
        guard let macro = macro(id: id) else {
            return PlaybackResult(outcome: .failed(.macroNotFound(id)), stepsCompleted: 0, totalSteps: 0,
                                  stoppedAt: nil, outputs: [], userInputGuardActive: false)
        }
        guard runningMacroID == nil, !recorder.isRecording else {
            return PlaybackResult(outcome: .failed(.busy), stepsCompleted: 0, totalSteps: 0,
                                  stoppedAt: nil, outputs: [], userInputGuardActive: false)
        }
        runningMacroID = id
        let (stream, continuation) = AsyncStream.makeStream(of: MacroProgress.self)
        let relay = Task { [weak self] in
            for await p in stream { self?.onProgress?(p, trigger) }
        }
        let player = self.player
        let opts = options ?? playbackOptions
        let task = Task.detached {
            await player.run(macro, options: opts) { continuation.yield($0) }
        }
        runTask = task
        let result = await task.value
        continuation.finish()
        await relay.value
        runTask = nil
        runningMacroID = nil
        onRunFinished?(id, trigger, result)
        return result
    }

    public func cancelRun() {
        runTask?.cancel()
    }

    /// Runs whatever macro is bound to a phone gesture. Returns nil when the
    /// gesture is not bound to anything.
    @discardableResult
    public func handleGesture(_ name: String) async -> PlaybackResult? {
        guard let m = TriggerRouter(macros: macros).macro(forGesture: name, activeProfile: activeProfile) else {
            return nil
        }
        return await run(m.id, trigger: .gesture(name))
    }

    /// Resolves a macro without running it (for the editor's preview and the phone).
    public func dryRun(_ id: UUID) throws -> [PlannedAction] {
        guard let m = macro(id: id) else { throw MacroError.macroNotFound(id) }
        return try player.dryRun(m, options: playbackOptions)
    }

    // MARK: Recording

    public var isRecording: Bool { recorder.isRecording }

    public func startRecording(options: RecordingOptions = .init()) throws {
        guard runningMacroID == nil else { throw MacroError.busy }
        try recorder.start(options: options, layout: KeyboardLayoutMap.current()) { [weak self] result in
            Self.onMain { self?.onRecordingStoppedByHotkey?(result) }
        }
    }

    /// Stops recording and returns what was captured. Set `fromMacMenu` when
    /// the user clicked a Mac control to stop, so that click is not kept.
    public func stopRecording(fromMacMenu: Bool = false) throws -> RecordingResult {
        try recorder.stop(discardTrailingClick: fromMacMenu)
    }

    /// An unsaved macro made from a recording, ready for the editor.
    public static func draft(from result: RecordingResult, name: String) -> Macro {
        Macro(name: name, symbol: "record.circle", color: "#FF453A", steps: result.steps, origin: .recorded)
    }
}
