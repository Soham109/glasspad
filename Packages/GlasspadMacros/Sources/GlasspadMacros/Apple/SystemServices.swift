import Foundation
import AppKit
import ApplicationServices
import Carbon
import UserNotifications

// MARK: - Apps and URLs

/// Opens apps, URLs and files with NSWorkspace.
public struct WorkspaceAppLauncher: AppLaunching {
    public init() {}

    public func openApp(bundleID: String) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw MacroError.appNotFound(bundleID: bundleID)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    public func open(url: URL) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.open(url, configuration: config)
    }
}

// MARK: - Frontmost window

/// Reads the frontmost app from NSWorkspace and its focused window's frame
/// from the Accessibility API. Without Accessibility it falls back to the
/// window server's list, which gives the same frame for the app's front window.
public struct AXWindowProvider: FrontmostWindowProviding {
    public init() {}

    public func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public func frontmostWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        if AXIsProcessTrusted(), let frame = Self.axFrame(pid: pid) { return frame }
        return Self.windowServerFrame(pid: pid)
    }

    static func axFrame(pid: pid_t) -> CGRect? {
        let appElement = AXUIElementCreateApplication(pid)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            let window = value as! AXUIElement
            var posRef: CFTypeRef?, sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let posRef, let sizeRef,
                  CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { continue }
            var origin = CGPoint.zero, size = CGSize.zero
            guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
                  AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { continue }
            return CGRect(origin: origin, size: size)
        }
        return nil
    }

    static func windowServerFrame(pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            return rect
        }
        return nil
    }
}

// MARK: - Clipboard

public struct PasteboardClipboard: ClipboardWriting {
    public init() {}
    public func setString(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

// MARK: - Notifications

/// Shows a Mac notification. Inside the signed app bundle it uses
/// UserNotifications; outside a bundle (command-line runs) that API is not
/// available, so it falls back to `osascript`'s `display notification`.
public struct SystemNotifier: Notifying {
    let runner: any ProcessRunning
    public init(runner: any ProcessRunning = SystemProcessRunner()) { self.runner = runner }

    static var canUseUserNotifications: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    public func notify(title: String, body: String) async throws {
        if Self.canUseUserNotifications {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                return
            }
        }
        // Arguments go through argv, so quotes in the text cannot break the script.
        _ = try await runner.run("/usr/bin/osascript", [
            "-e", "on run argv",
            "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
            "-e", "end run",
            title, body,
        ], timeoutMs: 10_000)
    }
}

// MARK: - Secure input

/// Real check: Carbon's `IsSecureEventInputEnabled`, true while any password
/// field is focused or Secure Keyboard Entry is on anywhere.
public struct SystemSecureInputChecker: SecureInputChecking {
    public init() {}
    public func isSecureInputEnabled() -> Bool { IsSecureEventInputEnabled() }
}

// MARK: - Scripts

/// AppleScript through NSAppleScript, and shell commands through `/bin/zsh -c`.
///
/// NSAppleScript is not safe to use from several threads at once, and running
/// it on the main thread would freeze the menu bar app while a script waits on
/// another app. So every script runs on one dedicated serial queue. If playback
/// is cancelled the player stops immediately; the script itself finishes on
/// that queue (an Apple event cannot be interrupted midway).
public struct SystemScriptRunner: ScriptRunning {
    static let appleScriptQueue = DispatchQueue(label: "app.glasspad.macros.applescript", qos: .userInitiated)
    let processRunner: any ProcessRunning

    public init(processRunner: any ProcessRunning = SystemProcessRunner()) {
        self.processRunner = processRunner
    }

    public func runAppleScript(_ source: String) async throws -> String? {
        let pending = LockedBox<CheckedContinuation<String?, Error>?>(nil)
        @Sendable func resume(_ result: Result<String?, Error>) {
            let cont = pending.update { c -> CheckedContinuation<String?, Error>? in defer { c = nil }; return c }
            cont?.resume(with: result)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String?, Error>) in
                pending.set(cont)
                if Task.isCancelled { resume(.failure(CancellationError())); return }
                Self.appleScriptQueue.async {
                    var errorInfo: NSDictionary?
                    guard let script = NSAppleScript(source: source) else {
                        resume(.failure(MacroError.appleScriptFailed("Could not create the script.")))
                        return
                    }
                    let result = script.executeAndReturnError(&errorInfo)
                    if let errorInfo {
                        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "\(errorInfo)"
                        resume(.failure(MacroError.appleScriptFailed(message)))
                    } else {
                        resume(.success(result.stringValue))
                    }
                }
            }
        } onCancel: {
            // Release the caller now; the script finishes on its queue.
            resume(.failure(CancellationError()))
        }
    }

    public func runShell(_ command: String, timeoutMs: Int) async throws -> String {
        let r = try await processRunner.run("/bin/zsh", ["-c", command], timeoutMs: timeoutMs)
        try Task.checkCancellation()
        if r.timedOut { throw MacroError.shellTimedOut }
        guard r.status == 0 else {
            throw MacroError.shellFailed(exitCode: r.status,
                                         stderr: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return r.stdout.trimmingCharacters(in: .newlines)
    }
}
