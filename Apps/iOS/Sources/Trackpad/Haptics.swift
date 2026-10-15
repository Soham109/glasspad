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

    init(_ kind: HapticKind) {
        switch kind {
        case .click: self = .click
        case .forceClick: self = .forceClickRamp
        case .detent: self = .detent
        case .snap: self = .snap
        case .error: self = .error
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
    private var wantsRunning = false
    private(set) var isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// Effective strength 0...1, recomputed from settings by the caller.
    var strength: Double = 0.7 {
        didSet { if abs(strength - builtStrength) > 0.01 { rebuildPlayers() } }
    }

    /// Set from the thermal monitor. When true, nothing plays.
    var suspendedForHeat = false

    /// Starts the engine ahead of the first touch so the first click has no start-up delay.
    func warmUp() {
        wantsRunning = true
        guard isSupported else { return }
        if engine == nil { makeEngine() }
        do {
            try engine?.start()
        } catch {
            engine = nil
            players = [:]
        }
        if players.isEmpty { rebuildPlayers() }
    }

    /// Lets the engine shut down when the trackpad is not on screen.
    func coolDown() {
        wantsRunning = false
        engine?.stop(completionHandler: nil)
    }

    func play(_ cue: HapticCue) {
        guard isSupported, !suspendedForHeat, strength > 0.01 else { return }
        if engine == nil { warmUp() }
        let key = HapticCueKey(cue)
        guard let player = players[key] else { return }
        do {
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // The engine was reset by the system; rebuild once and retry.
            warmUp()
            try? players[key]?.start(atTime: CHHapticTimeImmediate)
        }
    }

    /// For buttons in the modes: a light tap that follows the same strength and heat rules.
    func tap() { play(.detent) }

    private func makeEngine() {
        guard let engine = try? CHHapticEngine() else { return }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        engine.stoppedHandler = { @Sendable _ in }
        engine.resetHandler = { @Sendable [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.players = [:]
                if self.wantsRunning {
                    try? self.engine?.start()
                    self.rebuildPlayers()
                }
            }
        }
        self.engine = engine
    }

    private func rebuildPlayers() {
        builtStrength = strength
        guard let engine else { return }
        var built: [HapticCueKey: CHHapticPatternPlayer] = [:]
        for key in HapticCueKey.allCases {
            if let pattern = try? key.pattern(strength: Float(strength)),
               let player = try? engine.makePlayer(with: pattern) {
                built[key] = player
            }
        }
        players = built
    }
}

/// Hashable twin of `HapticCue`, used as the player cache key.
private enum HapticCueKey: CaseIterable {
    case click, forceClickRamp, forceClickDeep, detent, snap, error

    init(_ cue: HapticCue) {
        switch cue {
        case .click: self = .click
        case .forceClickRamp: self = .forceClickRamp
        case .forceClickDeep: self = .forceClickDeep
        case .detent: self = .detent
        case .snap: self = .snap
        case .error: self = .error
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
        }
    }
}
