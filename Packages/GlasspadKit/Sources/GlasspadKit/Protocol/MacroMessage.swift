import Foundation

/// What the phone needs to draw one macro button (docs/SPEC-macros.md section 6).
/// Mirrors `GlasspadMacros.MacroSummary`; the Mac converts between the two.
public struct MacroSummary: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// SF Symbol name for the button.
    public var symbol: String
    /// Button colour as `#RRGGBB`.
    public var color: String
    public var stepCount: Int
    /// True when the macro has shell or AppleScript steps (the phone may show a badge).
    public var usesScripts: Bool

    public init(id: UUID, name: String, symbol: String, color: String, stepCount: Int, usesScripts: Bool) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.stepCount = stepCount
        self.usesScripts = usesScripts
    }

    /// `color` as 0...1 components, nil when it is not a valid `#RRGGBB` string.
    public var rgb: (red: Double, green: Double, blue: Double)? {
        var hex = color.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return (Double(v >> 16 & 0xFF) / 255, Double(v >> 8 & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

/// The profile that matches the Mac's frontmost app, with its buttons in order.
public struct ActiveProfileInfo: Codable, Equatable, Sendable {
    /// nil when no profile matched and every macro is shown.
    public var profileID: UUID?
    public var name: String
    public var symbol: String
    /// The frontmost app's bundle id, when known.
    public var bundleID: String?
    public var macros: [MacroSummary]

    public init(profileID: UUID?, name: String, symbol: String, bundleID: String?, macros: [MacroSummary]) {
        self.profileID = profileID
        self.name = name
        self.symbol = symbol
        self.bundleID = bundleID
        self.macros = macros
    }
}

/// Playback progress, sent before each step and once at the end.
public struct MacroProgress: Codable, Equatable, Sendable {
    public var macroID: UUID
    public var completedSteps: Int
    public var totalSteps: Int
    /// Index path of the step about to run; empty when finished.
    public var currentPath: [Int]
    public var currentSummary: String

    public init(macroID: UUID, completedSteps: Int, totalSteps: Int, currentPath: [Int], currentSummary: String) {
        self.macroID = macroID
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
        self.currentPath = currentPath
        self.currentSummary = currentSummary
    }

    /// 0...1, 1 when there are no steps.
    public var fraction: Double { totalSteps == 0 ? 1 : Double(completedSteps) / Double(totalSteps) }
}

/// How a macro run ended.
public enum RunOutcome: String, Codable, Sendable, CaseIterable {
    case completed, cancelled, interruptedByUser, failed
}

/// Macros mode, carried inside `ModeMessage.macro`. Direction is noted on each case.
/// JSON with a `"t"` discriminator, e.g. `{"t":"run","macroID":"…"}`.
public enum MacroMessage: Codable, Equatable, Sendable {
    // Phone -> Mac
    /// Phone -> Mac: send the macro list. Reply: `macroList`.
    case listMacros
    /// Phone -> Mac: run this macro (a button on the Macros screen).
    case run(macroID: UUID)
    /// Phone -> Mac: a named phone gesture (for example "fourFingerTap"); runs the macro bound to it, if any.
    case gesture(name: String)
    /// Phone -> Mac: stop the macro that is playing.
    case cancelRun
    /// Phone -> Mac: start recording the Mac's keyboard and mouse. Reply: `recordingState` or `recordingFailed`.
    case recordStart(windowRelative: Bool, keepTiming: Bool)
    /// Phone -> Mac: stop recording and save the macro. Reply: `recordingFinished`.
    case recordStop

    // Mac -> phone
    /// Mac -> phone: the active profile's buttons, and every macro.
    case macroList(active: ActiveProfileInfo, all: [MacroSummary])
    /// Mac -> phone: sent on every frontmost-app profile switch and after macros are edited.
    case activeProfileChanged(ActiveProfileInfo)
    /// Mac -> phone: before each step and once at the end.
    case progress(MacroProgress)
    /// Mac -> phone: a run ended. `message` explains a failure; `outputs` are text from shortcuts and scripts.
    case runFinished(macroID: UUID, outcome: RunOutcome, message: String?, outputs: [String])
    /// Mac -> phone: recording started or stopped (also when the Mac hotkey or menu does it).
    case recordingState(isRecording: Bool)
    /// Mac -> phone: the recording was saved as this macro.
    case recordingFinished(macro: MacroSummary, droppedSecureKeys: Int)
    /// Mac -> phone: recording could not start or could not be saved (for example a password field
    /// is focused, or Input Monitoring is not allowed). Shown to the user as is.
    case recordingFailed(message: String)

    private enum Keys: String, CodingKey {
        case t, macroID, name, windowRelative, keepTiming, active, all, progress
        case outcome, message, outputs, isRecording, macro, droppedSecureKeys
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "listMacros": self = .listMacros
        case "run": self = .run(macroID: try c.decode(UUID.self, forKey: .macroID))
        case "gesture": self = .gesture(name: try c.decode(String.self, forKey: .name))
        case "cancelRun": self = .cancelRun
        case "recordStart":
            self = .recordStart(windowRelative: try c.decodeIfPresent(Bool.self, forKey: .windowRelative) ?? false,
                                keepTiming: try c.decodeIfPresent(Bool.self, forKey: .keepTiming) ?? true)
        case "recordStop": self = .recordStop
        case "macroList":
            self = .macroList(active: try c.decode(ActiveProfileInfo.self, forKey: .active),
                              all: try c.decode([MacroSummary].self, forKey: .all))
        case "activeProfileChanged": self = .activeProfileChanged(try c.decode(ActiveProfileInfo.self, forKey: .active))
        case "progress": self = .progress(try c.decode(MacroProgress.self, forKey: .progress))
        case "runFinished":
            self = .runFinished(macroID: try c.decode(UUID.self, forKey: .macroID),
                                outcome: try c.decode(RunOutcome.self, forKey: .outcome),
                                message: try c.decodeIfPresent(String.self, forKey: .message),
                                outputs: try c.decodeIfPresent([String].self, forKey: .outputs) ?? [])
        case "recordingState": self = .recordingState(isRecording: try c.decode(Bool.self, forKey: .isRecording))
        case "recordingFinished":
            self = .recordingFinished(macro: try c.decode(MacroSummary.self, forKey: .macro),
                                      droppedSecureKeys: try c.decodeIfPresent(Int.self, forKey: .droppedSecureKeys) ?? 0)
        case "recordingFailed": self = .recordingFailed(message: try c.decode(String.self, forKey: .message))
        default:
            throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "unknown macro message \(t)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .listMacros: try c.encode("listMacros", forKey: .t)
        case .run(let id):
            try c.encode("run", forKey: .t)
            try c.encode(id, forKey: .macroID)
        case .gesture(let name):
            try c.encode("gesture", forKey: .t)
            try c.encode(name, forKey: .name)
        case .cancelRun: try c.encode("cancelRun", forKey: .t)
        case .recordStart(let windowRelative, let keepTiming):
            try c.encode("recordStart", forKey: .t)
            try c.encode(windowRelative, forKey: .windowRelative)
            try c.encode(keepTiming, forKey: .keepTiming)
        case .recordStop: try c.encode("recordStop", forKey: .t)
        case .macroList(let active, let all):
            try c.encode("macroList", forKey: .t)
            try c.encode(active, forKey: .active)
            try c.encode(all, forKey: .all)
        case .activeProfileChanged(let active):
            try c.encode("activeProfileChanged", forKey: .t)
            try c.encode(active, forKey: .active)
        case .progress(let p):
            try c.encode("progress", forKey: .t)
            try c.encode(p, forKey: .progress)
        case .runFinished(let id, let outcome, let message, let outputs):
            try c.encode("runFinished", forKey: .t)
            try c.encode(id, forKey: .macroID)
            try c.encode(outcome, forKey: .outcome)
            try c.encodeIfPresent(message, forKey: .message)
            try c.encode(outputs, forKey: .outputs)
        case .recordingState(let on):
            try c.encode("recordingState", forKey: .t)
            try c.encode(on, forKey: .isRecording)
        case .recordingFinished(let macro, let dropped):
            try c.encode("recordingFinished", forKey: .t)
            try c.encode(macro, forKey: .macro)
            try c.encode(dropped, forKey: .droppedSecureKeys)
        case .recordingFailed(let message):
            try c.encode("recordingFailed", forKey: .t)
            try c.encode(message, forKey: .message)
        }
    }
}
