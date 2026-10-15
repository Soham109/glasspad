import CoreHaptics
import GlasspadKit
import UIKit

/// The haptic patterns Glasspad plays. The local gesture recognizer decides when;
/// this class only plays them, as fast as Core Haptics allows.
enum HapticCue: Sendable {
    case click
    case forceClickRamp   // still hold reached force click stage 1
    case forceClickDeep   // stage 2, a sharp tick
    case detent
    case snap
    case error
    case dragLock         // a tap-drag picked something up

    init(_ kind: HapticKind) {
        switch kind {
        case .click: self = .click
        case .forceClick: self = .forceClickRamp
        case .detent: self = .detent
        case .snap: self = .snap
        case .error: self = .error
        case .dragLock: self = .dragLock
        }
    }
}

/// A pre-warmed `CHHapticEngine` with one ready player per cue, so a cue costs one
/// `start` call. Strength = phone slider x Mac click firmness. Silent when the phone is
/// warm (`thermalState >= .serious`) or when the hardware has no Taptic Engine.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private var engine: CHHapticEngine?
    private var players: [HapticCueKey: CHHapticPatternPlayer] = [:]
    private var builtStrength: Double = -1
    /// The trackpad is on screen: keep the engine running.
    private var wantsRunning = false
    private var engineRunning = false
    private var idleStop: Task<Void, Never>?
    private(set) var isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// Effective strength 0...1, recomputed from settings by the caller.
    var strength: Double = 0.7 {
        didSet { if abs(strength - builtStrength) > 0.01 { rebuildPlayers() } }
    }

    /// Per-kind strengths (click, force click, drag lock) from the phone's tuning, 0...1 each.
    var tuning: TrackpadTuning = .default {
        didSet { if tuning != oldValue { rebuildPlayers() } }
    }

    /// Set from the thermal monitor. When true, nothing plays.
    var suspendedForHeat = false

    /// Starts the engine ahead of the first touch so the first click has no start-up delay, and
    /// keeps it running until `coolDown`.
    func warmUp() {
        wantsRunning = true
        idleStop?.cancel()
        idleStop = nil
        startEngine()
    }

    /// Lets the engine shut down when the trackpad is not on screen.
    func coolDown() {
        wantsRunning = false
        idleStop?.cancel()
        idleStop = nil
        stopEngine()
    }

    /// Starts (or restarts) the engine without asking for it to stay on.
    private func startEngine() {
        guard isSupported else { return }
        if engine == nil { makeEngine() }
        do {
            try engine?.start()
            engineRunning = engine != nil
        } catch {
            engine = nil
            players = [:]
            engineRunning = false
        }
        if players.isEmpty { rebuildPlayers() }
    }

    private func stopEngine() {
        engineRunning = false
        engine?.stop(completionHandler: nil)
    }

    /// Off the trackpad (mode buttons, Settings) a cue starts the engine only for a moment: it
    /// stops again after `idleStopDelay` without cues, so it does not keep the Taptic Engine
    /// powered (auto shutdown is off for the trackpad's sake).
    private func scheduleIdleStop() {
        idleStop?.cancel()
        idleStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.idleStopDelay))
            guard let self, !Task.isCancelled, !self.wantsRunning else { return }
            self.idleStop = nil
            self.stopEngine()
        }
    }

    static let idleStopDelay: TimeInterval = 2

    /// Plays a cue unless that kind is switched off in Settings > Haptic Types.
    func play(_ cue: HapticCue) {
        guard !PhoneSettings.shared.hapticsOff.contains(HapticChannel(cue)) else { return }
        start(cue)
    }

    private func start(_ cue: HapticCue) {
        guard isSupported, !suspendedForHeat, strength > 0.01 else { return }
        if !engineRunning { startEngine() }
        if !wantsRunning { scheduleIdleStop() }
        let key = HapticCueKey(cue)
        guard let player = players[key] else { return }
        do {
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // The engine was reset or stopped by the system; restart once and retry.
            startEngine()
            try? players[key]?.start(atTime: CHHapticTimeImmediate)
        }
    }

    /// For buttons in the modes: a light tap that follows the same strength and heat rules.
    /// Follows the "Buttons in modes" switch rather than the scroll-step one.
    func tap() {
        guard !PhoneSettings.shared.hapticsOff.contains(.buttons) else { return }
        start(.detent)
    }

    private func makeEngine() {
        guard let engine = try? CHHapticEngine() else { return }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        engine.stoppedHandler = { @Sendable [weak self] _ in
            Task { @MainActor in self?.engineRunning = false }
        }
        engine.resetHandler = { @Sendable [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.players = [:]
                self.engineRunning = false
                // Off the trackpad the next cue restarts it (and rebuilds the players).
                if self.wantsRunning { self.startEngine() }
            }
        }
        self.engine = engine
    }

    private func rebuildPlayers() {
        builtStrength = strength
        guard let engine else { return }
        var built: [HapticCueKey: CHHapticPatternPlayer] = [:]
        for key in HapticCueKey.allCases {
            let s = strength * key.scale(tuning)
            guard s > 0.01 else { continue }
            if let pattern = try? key.pattern(strength: Float(s)),
               let player = try? engine.makePlayer(with: pattern) {
                built[key] = player
            }
        }
        players = built
    }
}

/// Hashable twin of `HapticCue`, used as the player cache key.
private enum HapticCueKey: CaseIterable {
    case click, forceClickRamp, forceClickDeep, detent, snap, error, dragLock

    /// The per-kind strength from the phone's tuning; mode buttons (detent) and the others stay 1.
    func scale(_ t: TrackpadTuning) -> Double {
        switch self {
        case .click: t.clickHaptic
        case .forceClickRamp, .forceClickDeep: t.forceClickHaptic
        case .dragLock: t.dragLockHaptic
        case .detent, .snap, .error: 1
        }
    }

    init(_ cue: HapticCue) {
        switch cue {
        case .click: self = .click
        case .forceClickRamp: self = .forceClickRamp
        case .forceClickDeep: self = .forceClickDeep
        case .detent: self = .detent
        case .snap: self = .snap
        case .error: self = .error
        case .dragLock: self = .dragLock
        }
    }

    func pattern(strength s: Float) throws -> CHHapticPattern {
        func tick(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, intensity * s)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }
        switch self {
        case .click:
            return try CHHapticPattern(events: [tick(0, 1.0, 0.75)], parameters: [])
        case .forceClickRamp:
            // A short swell that rises into a firm tick, like the Mac's first force click stage.
            let swell = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, 0.55 * s)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35),
            ], relativeTime: 0, duration: 0.12)
            let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 0.15),
                .init(relativeTime: 0.12, value: 1.0),
            ], relativeTime: 0)
            return try CHHapticPattern(events: [swell, tick(0.12, 1.0, 0.6)], parameterCurves: [curve])
        case .forceClickDeep:
            return try CHHapticPattern(events: [tick(0, 1.0, 1.0)], parameters: [])
        case .detent:
            return try CHHapticPattern(events: [tick(0, 0.5, 0.9)], parameters: [])
        case .snap:
            return try CHHapticPattern(events: [tick(0, 0.55, 0.5), tick(0.07, 1.0, 0.85)], parameters: [])
        case .error:
            return try CHHapticPattern(events: [tick(0, 0.6, 0.3), tick(0.1, 0.6, 0.3), tick(0.2, 0.6, 0.3)], parameters: [])
        case .dragLock:
            // Softer and duller than a click: something was picked up, not pressed.
            return try CHHapticPattern(events: [tick(0, 0.75, 0.45)], parameters: [])
        }
    }
}
