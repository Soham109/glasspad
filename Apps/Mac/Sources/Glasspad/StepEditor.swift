import GlasspadMacros
import SwiftUI

/// Every step type, with its title and symbol for the editor.
enum StepKind: String, CaseIterable, Hashable {
    case keystroke, typeText, click, moveMouse, drag, scroll, wait, waitForApp
    case openApp, openURL, openFile, runShortcut, runAppleScript, runShell, setClipboard, notify, repeatBlock

    init(_ step: MacroStep) {
        switch step {
        case .keystroke: self = .keystroke
        case .typeText: self = .typeText
        case .click: self = .click
        case .moveMouse: self = .moveMouse
        case .drag: self = .drag
        case .scroll: self = .scroll
        case .wait: self = .wait
        case .waitForApp: self = .waitForApp
        case .openApp: self = .openApp
        case .openURL: self = .openURL
        case .openFile: self = .openFile
        case .runShortcut: self = .runShortcut
        case .runAppleScript: self = .runAppleScript
        case .runShell: self = .runShell
        case .setClipboard: self = .setClipboard
        case .notify: self = .notify
        case .repeatBlock: self = .repeatBlock
        }
    }

    /// Kinds offered in "Add Step" (a repeat block is made by recording or by hand in JSON).
    static let addable: [StepKind] = allCases.filter { $0 != .repeatBlock }

    var title: String {
        switch self {
        case .keystroke: "Press Keys"
        case .typeText: "Type Text"
        case .click: "Click"
        case .moveMouse: "Move Pointer"
        case .drag: "Drag"
        case .scroll: "Scroll"
        case .wait: "Wait"
        case .waitForApp: "Wait for App"
        case .openApp: "Open App"
        case .openURL: "Open URL"
        case .openFile: "Open File"
        case .runShortcut: "Run Shortcut"
        case .runAppleScript: "Run AppleScript"
        case .runShell: "Run Shell Command"
        case .setClipboard: "Set Clipboard"
        case .notify: "Show Notification"
        case .repeatBlock: "Repeat"
        }
    }

    var symbol: String {
        switch self {
        case .keystroke: "command"
        case .typeText: "character.cursor.ibeam"
        case .click: "cursorarrow.click"
        case .moveMouse: "cursorarrow.motionlines"
        case .drag: "hand.draw"
        case .scroll: "scroll"
        case .wait: "hourglass"
        case .waitForApp: "app.badge.clock"
        case .openApp: "app.badge"
        case .openURL: "link"
        case .openFile: "doc"
        case .runShortcut: "square.2.layers.3d"
        case .runAppleScript: "applescript"
        case .runShell: "terminal"
        case .setClipboard: "doc.on.clipboard"
        case .notify: "bell"
        case .repeatBlock: "repeat"
        }
    }

    /// A sensible new step of this kind.
    var template: MacroStep {
        switch self {
        case .keystroke: .keystroke(KeyCombo("c", [.command]))
        case .typeText: .typeText("")
        case .click: .click(button: .left, at: .screen(0, 0), count: 1, modifiers: [])
        case .moveMouse: .moveMouse(to: .screen(0, 0))
        case .drag: .drag(button: .left, from: .screen(0, 0), to: .screen(100, 0), durationMs: 300)
        case .scroll: .scroll(dx: 0, dy: -100)
        case .wait: .wait(ms: 500)
        case .waitForApp: .waitForApp(bundleID: "", timeoutMs: 5000)
        case .openApp: .openApp(bundleID: "")
        case .openURL: .openURL("https://")
        case .openFile: .openFile(path: "~/")
        case .runShortcut: .runShortcut(nameOrID: "", input: nil)
        case .runAppleScript: .runAppleScript(source: "")
        case .runShell: .runShell(command: "", timeoutMs: 30_000)
        case .setClipboard: .setClipboard("")
        case .notify: .notify(title: "", body: "")
        case .repeatBlock: .repeatBlock(count: 2, steps: [])
        }
    }
}

/// Edits one step with plain fields. Values are kept as text while editing and checked on Save.
struct StepEditorSheet: View {
    let isNew: Bool
    let onSave: (MacroStep) -> Void
    @Environment(\.dismiss) private var dismiss

    private let kind: StepKind
    private let nested: [MacroStep]
    @State private var text1: String
    @State private var text2: String
    @State private var number1: Int
    @State private var number2: Int
    @State private var point1: PointFields
    @State private var point2: PointFields
    @State private var modifiers: KeyModifiers
    @State private var button: MouseButton

    struct PointFields: Equatable {
        var x: Double = 0
        var y: Double = 0
        /// nil = screen.
        var anchor: WindowAnchor?

        init(_ p: MacroPoint) {
            x = p.x
            y = p.y
            if case .frontWindow(let a) = p.reference { anchor = a }
        }

        var point: MacroPoint { MacroPoint(x: x, y: y, reference: anchor.map { .frontWindow($0) } ?? .screen) }
    }

    init(step: MacroStep, isNew: Bool, onSave: @escaping (MacroStep) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        kind = StepKind(step)
        var t1 = "", t2 = "", n1 = 0, n2 = 0
        var p1 = PointFields(.screen(0, 0)), p2 = PointFields(.screen(0, 0))
        var mods: KeyModifiers = [], btn = MouseButton.left
        var inner: [MacroStep] = []
        switch step {
        case .keystroke(let k): t1 = k.key.jsonName; mods = k.modifiers
        case .typeText(let t): t1 = t
        case .click(let b, let p, let c, let m): btn = b; p1 = PointFields(p); n1 = c; mods = m
        case .moveMouse(let p): p1 = PointFields(p)
        case .drag(let b, let f, let t, let d): btn = b; p1 = PointFields(f); p2 = PointFields(t); n1 = d
        case .scroll(let dx, let dy): n1 = dx; n2 = dy
        case .wait(let ms): n1 = ms
        case .waitForApp(let id, let t): t1 = id; n1 = t
        case .openApp(let id): t1 = id
        case .openURL(let u): t1 = u
        case .openFile(let p): t1 = p
        case .runShortcut(let n, let input): t1 = n; t2 = input ?? ""
        case .runAppleScript(let s): t1 = s
        case .runShell(let c, let t): t1 = c; n1 = t
        case .setClipboard(let t): t1 = t
        case .notify(let t, let b): t1 = t; t2 = b
        case .repeatBlock(let c, let s): n1 = c; inner = s
        }
        nested = inner
        _text1 = State(initialValue: t1)
        _text2 = State(initialValue: t2)
        _number1 = State(initialValue: n1)
        _number2 = State(initialValue: n2)
        _point1 = State(initialValue: p1)
        _point2 = State(initialValue: p2)
        _modifiers = State(initialValue: mods)
        _button = State(initialValue: btn)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    fields
                } header: {
                    Label(kind.title, systemImage: kind.symbol)
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(.orange)
                    } else if let hint {
                        Text(hint).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    if let step = built {
                        onSave(step)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(built == nil)
            }
            .padding(12)
        }
        .frame(width: 440)
        .frame(minHeight: 260)
    }

    @ViewBuilder
    private var fields: some View {
        switch kind {
        case .keystroke:
            TextField("Key", text: $text1, prompt: Text("c, return, f5, left, code:93"))
            ModifierToggles(modifiers: $modifiers)
        case .typeText:
            TextField("Text", text: $text1, axis: .vertical)
                .lineLimit(3...8)
        case .click:
            Picker("Button", selection: $button) { buttonOptions }
            Picker("Clicks", selection: $number1) {
                Text("Single").tag(1)
                Text("Double").tag(2)
                Text("Triple").tag(3)
            }
            PointEditor(title: "At", point: $point1)
            ModifierToggles(modifiers: $modifiers)
        case .moveMouse:
            PointEditor(title: "To", point: $point1)
        case .drag:
            Picker("Button", selection: $button) { buttonOptions }
            PointEditor(title: "From", point: $point1)
            PointEditor(title: "To", point: $point2)
            TextField("Duration (ms)", value: $number1, format: .number)
        case .scroll:
            TextField("Horizontal (px)", value: $number1, format: .number)
            TextField("Vertical (px)", value: $number2, format: .number)
        case .wait:
            TextField("Milliseconds", value: $number1, format: .number)
        case .waitForApp:
            TextField("App bundle ID", text: $text1, prompt: Text("com.apple.Safari"))
            TextField("Give up after (ms)", value: $number1, format: .number)
        case .openApp:
            TextField("App bundle ID", text: $text1, prompt: Text("com.apple.Safari"))
            if !text1.isEmpty { LabeledContent("App", value: AppInfo.name(for: text1)) }
        case .openURL:
            TextField("URL", text: $text1, prompt: Text("https://example.com"))
        case .openFile:
            TextField("Path", text: $text1, prompt: Text("~/Documents/notes.txt"))
        case .runShortcut:
            TextField("Shortcut name", text: $text1)
            TextField("Input text (optional)", text: $text2)
        case .runAppleScript:
            TextField("AppleScript", text: $text1, axis: .vertical)
                .lineLimit(4...12)
                .font(.body.monospaced())
        case .runShell:
            TextField("Command", text: $text1, axis: .vertical)
                .lineLimit(2...8)
                .font(.body.monospaced())
            TextField("Time limit (ms)", value: $number1, format: .number)
        case .setClipboard:
            TextField("Text", text: $text1, axis: .vertical)
                .lineLimit(2...6)
        case .notify:
            TextField("Title", text: $text1)
            TextField("Message", text: $text2)
        case .repeatBlock:
            TextField("Times", value: $number1, format: .number)
            LabeledContent("Steps inside", value: "\(nested.count)")
        }
    }

    @ViewBuilder
    private var buttonOptions: some View {
        Text("Left").tag(MouseButton.left)
        Text("Right").tag(MouseButton.right)
        Text("Middle").tag(MouseButton.middle)
    }

    private var hint: String? {
        switch kind {
        case .keystroke: "A single character means the key that types it, so shortcuts work on any keyboard layout."
        case .typeText: "New lines and tabs are typed as Return and Tab."
        case .runAppleScript, .runShell: "Runs only when the macro's \"Allow scripts\" is on."
        case .click, .moveMouse, .drag: "Screen points from the top left of the main display, or offsets from a corner of the front window."
        default: nil
        }
    }

    private var problem: String? {
        switch kind {
        case .keystroke where MacroKey(jsonName: text1.trimmingCharacters(in: .whitespaces)) == nil && !text1.isEmpty:
            "Not a key. Use one character, a name like return or f5, or code:NN."
        case .openURL where !text1.isEmpty && URL(string: text1)?.scheme == nil:
            "A URL needs a scheme, like https://."
        case .wait where number1 < 0, .waitForApp where number1 < 0, .drag where number1 < 0, .runShell where number1 <= 0:
            "Use a positive number."
        case .repeatBlock where !(1...MacroPlayer.maxRepeatCount).contains(number1):
            "Repeat 1 to \(MacroPlayer.maxRepeatCount) times."
        default: nil
        }
    }

    /// The step, or nil while a field is incomplete.
    private var built: MacroStep? {
        guard problem == nil else { return nil }
        let t1 = text1.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .keystroke:
            guard let key = MacroKey(jsonName: t1) else { return nil }
            return .keystroke(KeyCombo(key, modifiers))
        case .typeText: return text1.isEmpty ? nil : .typeText(text1)
        case .click: return .click(button: button, at: point1.point, count: number1, modifiers: modifiers)
        case .moveMouse: return .moveMouse(to: point1.point)
        case .drag: return .drag(button: button, from: point1.point, to: point2.point, durationMs: number1)
        case .scroll: return (number1 == 0 && number2 == 0) ? nil : .scroll(dx: number1, dy: number2)
        case .wait: return .wait(ms: number1)
        case .waitForApp: return t1.isEmpty ? nil : .waitForApp(bundleID: t1, timeoutMs: number1)
        case .openApp: return t1.isEmpty ? nil : .openApp(bundleID: t1)
        case .openURL: return t1.isEmpty ? nil : .openURL(t1)
        case .openFile: return t1.isEmpty ? nil : .openFile(path: t1)
        case .runShortcut:
            return t1.isEmpty ? nil : .runShortcut(nameOrID: t1, input: text2.isEmpty ? nil : text2)
        case .runAppleScript: return t1.isEmpty ? nil : .runAppleScript(source: text1)
        case .runShell: return t1.isEmpty ? nil : .runShell(command: text1, timeoutMs: number1)
        case .setClipboard: return .setClipboard(text1)
        case .notify: return t1.isEmpty ? nil : .notify(title: t1, body: text2)
        case .repeatBlock: return .repeatBlock(count: number1, steps: nested)
        }
    }
}

private struct ModifierToggles: View {
    @Binding var modifiers: KeyModifiers

    var body: some View {
        LabeledContent("Modifiers") {
            HStack(spacing: 10) {
                toggle("⌃", "Control", .control)
                toggle("⌥", "Option", .option)
                toggle("⇧", "Shift", .shift)
                toggle("⌘", "Command", .command)
            }
        }
    }

    private func toggle(_ symbol: String, _ name: String, _ m: KeyModifiers) -> some View {
        Toggle(symbol, isOn: Binding(get: { modifiers.contains(m) },
                                     set: { on in if on { modifiers.insert(m) } else { modifiers.remove(m) } }))
            .toggleStyle(.button)
            .help(name)
            .accessibilityLabel(name)
    }
}

private struct PointEditor: View {
    let title: String
    @Binding var point: StepEditorSheet.PointFields

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                coordinate("X", $point.x)
                coordinate("Y", $point.y)
                Picker("Relative to", selection: $point.anchor) {
                    Text("Screen").tag(WindowAnchor?.none)
                    Divider()
                    Text("Window, top left").tag(WindowAnchor?.some(.topLeft))
                    Text("Window, top right").tag(WindowAnchor?.some(.topRight))
                    Text("Window, bottom left").tag(WindowAnchor?.some(.bottomLeft))
                    Text("Window, bottom right").tag(WindowAnchor?.some(.bottomRight))
                    Text("Window, centre").tag(WindowAnchor?.some(.center))
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private func coordinate(_ axis: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Text(axis)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(axis, value: value, format: .number)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .accessibilityLabel("\(title) \(axis)")
        }
    }
}
