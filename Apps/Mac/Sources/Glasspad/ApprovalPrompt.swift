import AppKit
import GlasspadMacCore

/// "Allow “Soham's iPhone” to control this Mac?" with Allow and Don't Allow, in the standard
/// macOS alert, before a newly paired iPhone is saved. Shown in front of everything (the code
/// may be in the menu bar popover, which closes when the alert comes up). Nobody answering
/// within the timeout counts as Don't Allow.
///
/// The alert runs without a modal loop: its buttons call back here, so the main thread keeps
/// serving the connected phone and the timeout can close it.
@MainActor
enum ApprovalPrompt {
    static func ask(phoneName: String, timeout: TimeInterval,
                    answer: @escaping @MainActor (Bool) -> Void) -> @MainActor () -> Void {
        let (alert, allow, dontAllow) = makeAlert(phoneName: phoneName)
        let handler = Handler(alert: alert, answer: answer)
        for (button, allowed) in [(allow, true), (dontAllow, false)] {
            button.target = handler
            button.action = allowed ? #selector(Handler.allow) : #selector(Handler.dontAllow)
        }
        alert.layout()
        let window = alert.window
        window.level = .floating
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { handler.finish(false) }
        return { handler.close() }
    }

    /// The alert and its two buttons, not shown yet (tests check the keys without a window).
    static func makeAlert(phoneName: String) -> (NSAlert, allow: NSButton, dontAllow: NSButton) {
        let alert = NSAlert()
        alert.messageText = ApprovalCopy.title(phoneName)
        alert.informativeText = ApprovalCopy.detail
        let allow = alert.addButton(withTitle: ApprovalCopy.allow)
        // Allow needs a click: NSAlert makes the first button answer Return, and this alert takes
        // focus while the person may be typing.
        allow.keyEquivalent = ""
        let dontAllow = alert.addButton(withTitle: ApprovalCopy.dontAllow)
        dontAllow.keyEquivalent = "\u{1b}"           // Escape
        return (alert, allow, dontAllow)
    }

    @MainActor private final class Handler: NSObject {
        private let alert: NSAlert
        private var answer: (@MainActor (Bool) -> Void)?

        init(alert: NSAlert, answer: @escaping @MainActor (Bool) -> Void) {
            self.alert = alert
            self.answer = answer
        }

        @objc func allow() { finish(true) }
        @objc func dontAllow() { finish(false) }

        /// The first answer counts; the window goes either way.
        func finish(_ allowed: Bool) {
            guard let answer else { return }
            self.answer = nil
            alert.window.orderOut(nil)
            answer(allowed)
        }

        /// Taken down without an answer (the phone left, or pairing was cancelled).
        func close() {
            answer = nil
            alert.window.orderOut(nil)
        }
    }
}
