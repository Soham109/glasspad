import Foundation

public enum MacroError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The file was written by a newer Glasspad.
    case unsupportedFormatVersion(found: Int, supported: Int)
    case scriptsNotAllowed
    case invalidStep(path: [Int], reason: String)
    case noFrontWindow
    case appNotFound(bundleID: String)
    case invalidURL(String)
    case fileNotFound(String)
    case timedOutWaitingForApp(bundleID: String)
    case shortcutFailed(name: String, message: String)
    case appleScriptFailed(String)
    case shellFailed(exitCode: Int32, stderr: String)
    case shellTimedOut
    case accessibilityNotGranted
    case inputMonitoringNotGranted
    case secureInputActive
    case alreadyRecording
    case notRecording
    case busy
    case macroNotFound(UUID)
    case hotkeyUnavailable(String)
    case outputFailed(String)

    public var description: String {
        switch self {
        case .unsupportedFormatVersion(let f, let s):
            "This file uses format version \(f), but this Glasspad reads up to version \(s). Update Glasspad."
        case .scriptsNotAllowed:
            "This macro has shell or AppleScript steps. Turn on \"Allow scripts\" for it first."
        case .invalidStep(let p, let r): "Step \(p.map { String($0 + 1) }.joined(separator: ".")): \(r)"
        case .noFrontWindow: "No frontmost window to position the pointer against."
        case .appNotFound(let id): "No app with bundle id \(id) is installed."
        case .invalidURL(let u): "Not a valid URL: \(u)"
        case .fileNotFound(let p): "No file at \(p)"
        case .timedOutWaitingForApp(let id): "Timed out waiting for \(id) to come to the front."
        case .shortcutFailed(let n, let m): "Shortcut \"\(n)\" failed: \(m)"
        case .appleScriptFailed(let m): "AppleScript failed: \(m)"
        case .shellFailed(let code, let err): "Shell command exited with \(code): \(err)"
        case .shellTimedOut: "Shell command timed out."
        case .accessibilityNotGranted: "Glasspad needs Accessibility permission to press keys and click."
        case .inputMonitoringNotGranted: "Glasspad needs Input Monitoring permission to record."
        case .secureInputActive:
            "A password field or secure app has keyboard input locked, so recording is refused."
        case .alreadyRecording: "Already recording."
        case .notRecording: "Not recording."
        case .busy: "Another macro is running."
        case .macroNotFound(let id): "No macro with id \(id)."
        case .hotkeyUnavailable(let k): "The hotkey \(k) is taken by another app."
        case .outputFailed(let m): "Could not post the event: \(m)"
        }
    }
}
