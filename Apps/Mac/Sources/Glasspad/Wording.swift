import Foundation
import GlasspadKit
import GlasspadMacCore
import GlasspadMacros

// Words the Mac shows, kept in one place so they match the iPhone app's screens:
// Trackpad, Keyboard, Media, Dock, Actions (Pinned, Library), Macros. The phone's pairing
// screens say "Pair a Mac", "Scan the code", "Paste the Link Instead" and "Paired"; the phone
// tells people to "choose Pair Your iPhone" in this app's menu.

// MARK: - Pairing

enum PairingCopy {
    static let menuItem = "Pair Your iPhone…"
    static let title = "Pair Your iPhone"
    static let instruction = "On your iPhone, open Glasspad, tap Pair a Mac and hold it over this code. Then click Allow on this Mac."
    static let showText = "Show Code as Text"
    static let showCode = "Show Code"
    static let linkHelp = "No camera? Copy the link, then on your iPhone tap Paste the Link Instead."
    static let copyLink = "Copy Link"
    static let copied = "Copied"
    static let share = "Share…"
    static let newCode = "Show a New Code"
    static let tryAgain = "Try Again"

    static func heading(_ phase: PairingPhase) -> String {
        switch phase {
        case .idle, .waiting: title
        case .approving(let name): "Allow \(name)?"
        case .paired(let name): "Paired with \(name)"
        case .declined: "Not Allowed"
        case .expired: "Code Expired"
        case .failed: "Pairing Did Not Finish"
        }
    }

    static func detail(_ phase: PairingPhase) -> String {
        switch phase {
        case .idle, .waiting: instruction
        case .approving: "Choose Allow or Don't Allow in the message on this Mac."
        case .paired: "Your iPhone now controls this Mac. Glasspad stays in the menu bar."
        case .declined(let name): "\(name) cannot control this Mac. To pair an iPhone, show a new code."
        case .expired: "Codes work for \(Int(PairingFlow.codeLifetime / 60)) minutes. Show a new one to pair."
        case .failed(let message): "\(message) Try again, and keep both on the same Wi-Fi."
        }
    }
}

/// The question the Mac asks before a new iPhone may control it (ApprovalPrompt.swift).
enum ApprovalCopy {
    static func title(_ phoneName: String) -> String { "Allow \u{201C}\(phoneName)\u{201D} to control this Mac?" }
    static let detail = "It can move the pointer, click and type on this Mac. Allow only your own iPhone."
    static let allow = "Allow"
    static let dontAllow = "Don't Allow"
}

// MARK: - Welcome

/// The first-run window (SetupViews.swift).
enum WelcomeCopy {
    static let helloTitle = "Welcome to Glasspad"
    static let helloDetail = "A control surface for your Mac, on your iPhone."
    static let permissionsTitle = "Let Your iPhone Control This Mac"
    static let permissionsDetail = "macOS asks you once. Glasspad only acts on what you do on your iPhone."
    static let permissionsFooter = "In System Settings, turn on Glasspad. This step finishes by itself."
    static let openSettings = "Open System Settings…"
    static let getIPhoneApp = "Get Glasspad for iPhone"
    static let iPhoneAppURL = URL(string: "https://github.com/Soham109/glasspad#install")!
    static let continueTitle = "Continue"
    static let back = "Back"
    static let skip = "Skip for Now"
    static let later = "Later"
    static let done = "Done"
    static let allSet = "You're All Set"
}

// MARK: - iPhone app renewal

/// Settings > iPhone, "iPhone App": the install that scripts/install-phone.sh made and the
/// hourly renewal that keeps it working past the free account's 7 days.
enum RenewalCopy {
    static let section = "iPhone App"
    static let showLog = "Show Log"
    /// A free account's install stops opening this long after it was made.
    static let lifetime: TimeInterval = 7 * 86_400

    /// The row's first line: how it stands, or what went wrong.
    static func title(_ s: PhoneInstallStatus) -> String {
        switch s.lastCheck?.result {
        case .notReachable: "Could not renew: the iPhone was not on this Wi-Fi."
        case .failed: "Could not renew: the install did not finish."
        default: s.renewsByItself ? "Installed \(day(s.installedAt)). Renews by itself."
            : "Installed \(day(s.installedAt)). Works until \(day(s.installedAt + lifetime))."
        }
    }

    /// The second line: what to do, what it is waiting for, and when it last looked.
    static func detail(_ s: PhoneInstallStatus, now: Date = Date()) -> String? {
        guard s.renewsByItself else { return "Renew by running scripts/setup-autorefresh.sh once." }
        guard let check = s.lastCheck else { return nil }
        let checked = "Last checked \(time(check.checkedAt, now: now))."
        switch check.result {
        case .notReachable, .failed: return "Works until \(day(s.installedAt + lifetime)). \(checked)"
        case .waitingInUse: return "Waiting until Glasspad is not in use on the iPhone. \(checked)"
        case .renewed, .tooEarly: return checked
        }
    }

    /// "Oct 16".
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "10:42 AM" today, "Oct 15, 10:42 AM" before.
    static func time(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

// MARK: - Permissions

enum PermissionCopy {
    static let accessibilityTitle = "Accessibility"
    static let accessibilityDetail = "Lets your iPhone move the pointer, click, scroll and type."
    static let accessibilityHint = "Opens Privacy & Security, Accessibility in System Settings"
    static let required = "Required"

    static let mediaTitle = "Spotify and Music"
    static let optional = "Optional"
    static let mediaHint = "Opens Privacy & Security, Automation in System Settings"

    static func mediaDetail(_ state: AutomationState, denied: [String]) -> String {
        switch state {
        case .granted: "Shows what is playing on your iPhone's Media screen."
        case .denied:
            denied.isEmpty
                ? "Not allowed. Media still works, without what is playing."
                : "Not allowed for \(denied.formatted(.list(type: .and))). Media still works, without what is playing."
        case .notDetermined: "Shows what is playing on your iPhone's Media screen. macOS asks the first time."
        case .notNeeded: "Neither app is on this Mac, so nothing to allow."
        }
    }

    static let askAfterAccessibility = "Allow Accessibility first."
    static let openPlayerFirst = "Open Spotify or Music, then ask again. Or skip this: macOS asks the first time you use Media."
}

// MARK: - Gesture overrides

/// Settings > Trackpad, "If a gesture stops working", and the Diagnostics list.
enum GestureCopy {
    static let sectionTitle = "If a Gesture Stops Working"
    static let footer = "If a gesture stops working after a macOS update, choose Keyboard shortcut for it."

    /// The choice as the picker shows it.
    static func choice(_ p: GesturePreference) -> String {
        switch p {
        case .automatic: "Automatic"
        case .native: "Trackpad gesture"
        case .keyboardShortcut: "Keyboard shortcut"
        }
    }

    /// The line under a gesture's name: what reaches the Mac now. None while it goes as a
    /// trackpad gesture, which the section's footer already says.
    static func inUse(_ mode: SynthMode) -> String? {
        switch mode {
        case .native: nil
        case .fallback: "Now sent as a keyboard shortcut"
        case .unavailable: "Not available on this Mac"
        }
    }

    /// Gestures that have a choice to make (both a trackpad gesture and a shortcut).
    static var adjustable: [SynthGesture] {
        SynthGesture.allCases.filter { GesturePreference.options(for: $0).count > 1 }
    }

    /// Diagnostics: the path in use, and whether the user picked it.
    static func diagnostics(_ mode: SynthMode, preference: GesturePreference) -> String {
        preference == .automatic ? mode.label : "\(mode.label), your choice"
    }
}

// MARK: - Gestures

/// Phone gestures a macro can be bound to, with the names people read.
enum GestureNames {
    static let catalog: [(id: String, title: String)] = [
        ("fourFingerTap", "Four-finger tap"),
        ("fourFingerDoubleTap", "Four-finger double tap"),
        ("fiveFingerTap", "Five-finger tap"),
        ("threeFingerDoubleTap", "Three-finger double tap"),
    ]

    /// "fourFingerTap" -> "Four-finger tap". Names not in the catalog (from a hand-edited file)
    /// are split at capitals, so no raw identifier reaches the screen.
    static func title(for id: String) -> String {
        if let known = catalog.first(where: { $0.id == id }) { return known.title }
        var words: [String] = []
        var current = ""
        for ch in id {
            if ch.isUppercase, !current.isEmpty { words.append(current); current = "" }
            current.append(ch)
        }
        if !current.isEmpty { words.append(current) }
        let numbers = ["one": "One", "two": "Two", "three": "Three", "four": "Four", "five": "Five"]
        var out: [String] = []
        var i = 0
        while i < words.count {
            let w = words[i].lowercased()
            if numbers[w] != nil, i + 1 < words.count, words[i + 1].lowercased() == "finger" {
                out.append("\(w)-finger")
                i += 2
                continue
            }
            out.append(w)
            i += 1
        }
        guard let first = out.first else { return id }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + out.dropFirst()).joined(separator: " ")
    }
}

// MARK: - Keys

enum KeyCaption {
    /// What a key is called in the key picker.
    static func name(_ key: GlasspadMacros.SpecialKey) -> String {
        switch key {
        case .returnKey: "Return ↩"
        case .tab: "Tab ⇥"
        case .space: "Space"
        case .delete: "Delete ⌫"
        case .forwardDelete: "Forward Delete ⌦"
        case .escape: "Escape ⎋"
        case .left: "Left Arrow ←"
        case .right: "Right Arrow →"
        case .up: "Up Arrow ↑"
        case .down: "Down Arrow ↓"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "Page Up"
        case .pageDown: "Page Down"
        case .keypadEnter: "Keypad Enter ⌤"
        case .help: "Help"
        default: key.rawValue.uppercased()
        }
    }

    /// The key's cap as macOS menus print it: "Space", "Return", "F5", "←", "T".
    static func cap(_ key: MacroKey) -> String {
        switch key {
        case .character(let c): c.uppercased()
        case .special(let s):
            switch s {
            case .returnKey: "Return"
            case .tab: "Tab"
            case .escape: "Esc"
            case .delete: "Delete"
            case .forwardDelete: "Forward Delete"
            case .pageUp: "Page Up"
            case .pageDown: "Page Down"
            case .home: "Home"
            case .end: "End"
            case .keypadEnter: "Enter"
            default: s.symbol
            }
        case .code: "Recorded Key"
        }
    }

    /// "⌘ Space", "⇧⌘ T", "Return".
    static func caption(_ combo: KeyCombo) -> String {
        let mods = combo.modifiers.symbols
        return mods.isEmpty ? cap(combo.key) : "\(mods) \(cap(combo.key))"
    }
}

// MARK: - Steps

enum StepText {
    /// One line per step, with app names instead of bundle IDs and plain key captions.
    static func summary(_ step: MacroStep, appName: (String) -> String) -> String {
        switch step {
        case .keystroke(let k): "Press \(KeyCaption.caption(k))"
        case .click(let b, let p, let n, let m):
            [n == 2 ? "Double-click" : n == 3 ? "Triple-click" : "Click",
             b == .left ? nil : (b == .right ? "right button" : "middle button"),
             m.isEmpty ? nil : "holding \(m.symbols)",
             "at \(point(p))"].compactMap { $0 }.joined(separator: " ")
        case .moveMouse(let p): "Move pointer to \(point(p))"
        case .drag(_, let a, let b, _): "Drag from \(point(a)) to \(point(b))"
        case .scroll(let dx, let dy): scroll(dx: dx, dy: dy)
        case .wait(let ms): "Wait \(seconds(ms))"
        case .waitForApp(let id, let t): "Wait for \(appName(id)) (up to \(seconds(t)))"
        case .openApp(let id): "Open \(appName(id))"
        default: step.summary
        }
    }

    static func point(_ p: MacroPoint) -> String {
        let xy = "\(Int(p.x)), \(Int(p.y))"
        switch p.reference {
        case .screen: return xy
        case .frontWindow(let a): return "\(xy) from the window's \(anchor(a))"
        }
    }

    static func anchor(_ a: WindowAnchor) -> String {
        switch a {
        case .topLeft: "top left"
        case .topRight: "top right"
        case .bottomLeft: "bottom left"
        case .bottomRight: "bottom right"
        case .center: "center"
        }
    }

    static func seconds(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms) ms" }
        let s = Double(ms) / 1000
        return "\(s.formatted(.number.precision(.fractionLength(0...1)))) s"
    }

    static func scroll(dx: Int, dy: Int) -> String {
        var parts: [String] = []
        if dy != 0 { parts.append(dy < 0 ? "down \(-dy)" : "up \(dy)") }
        if dx != 0 { parts.append(dx > 0 ? "left \(dx)" : "right \(-dx)") }   // positive dx scrolls left
        return "Scroll " + parts.joined(separator: ", ")
    }
}
