import SwiftUI
import UIKit
import GlasspadKit

/// Type on the phone, it appears on the Mac as you type. Dictation works because the text
/// is read from the field after iOS has inserted it, whichever way it got there.
struct KeysMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.verticalSizeClass) private var verticalSize
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    private let accent = AppMode.keys.accent(.paper)

    @State private var modifiers: KeyModifiers = []
    @State private var echo = ""
    @State private var focusToken = 0

    var body: some View {
        Group {
            if verticalSize == .compact {
                // Sideways the keyboard takes most of the height, so the extra keys fold
                // into two rows and the echo shrinks to one line.
                VStack(spacing: 10) {
                    Spacer(minLength: 22)
                    echoLine
                    HStack(spacing: 8) {
                        if settings.leftHanded {
                            arrowKeys(compact: true)
                            sideKeys
                            modifierRow
                        } else {
                            modifierRow
                            sideKeys
                            arrowKeys(compact: true)
                        }
                    }
                    .frame(height: 44)
                    shortcutRow
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            } else {
                VStack(spacing: 14) {
                    Spacer(minLength: 64)
                    echoArea
                    modifierRow
                    shortcutRow
                    navigationRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .background {
            // The real input field sits under everything; it owns the keyboard.
            StreamingTextField(modifiers: $modifiers, echo: $echo, focusToken: focusToken) { output in
                send(output)
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { focusToken += 1 }
        .overlay {
            if !session.isConnected { ModeOfflineMessage(mode: .keys).background(palette.backgroundColor) }
        }
    }

    // MARK: Pieces

    private var echoArea: some View {
        VStack(spacing: 6) {
            Text(echo.isEmpty ? "Start typing" : echo)
                .font(.title2)
                .foregroundStyle(echo.isEmpty ? palette.inkSoftColor : palette.inkColor)
                .lineLimit(3)
                .truncationMode(.head)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 80)
                .contentTransition(.opacity)
                .animation(.snappy, value: echo.isEmpty)
            Text(modifiers.isEmpty ? "Text goes straight to your Mac" : "Next key: \(modifiers.symbols)")
                .font(.footnote)
                .foregroundStyle(modifiers.isEmpty ? palette.inkSoftColor : accent)
                .contentTransition(.numericText())
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var echoLine: some View {
        HStack(spacing: 10) {
            Text(echo.isEmpty ? "Start typing" : echo)
                .font(.headline.weight(.regular))
                .foregroundStyle(echo.isEmpty ? palette.inkSoftColor : palette.inkColor)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(modifiers.isEmpty ? "Text goes straight to your Mac" : "Next key: \(modifiers.symbols)")
                .font(.footnote)
                .foregroundStyle(modifiers.isEmpty ? palette.inkSoftColor : accent)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private var sideKeys: some View {
        HStack(spacing: 8) {
            key("esc", .escape, "Escape")
            key("tab", .tab, "Tab")
            key("delete.left", .delete, "Delete", symbol: true)
        }
    }

    /// Portrait stacks up over down between left and right; sideways all four sit in a row.
    @ViewBuilder private func arrowKeys(compact: Bool) -> some View {
        HStack(spacing: 6) {
            key("arrow.left", .left, "Left arrow", symbol: true)
            if compact {
                key("arrow.up", .up, "Up arrow", symbol: true)
                key("arrow.down", .down, "Down arrow", symbol: true)
            } else {
                VStack(spacing: 6) {
                    key("arrow.up", .up, "Up arrow", symbol: true)
                    key("arrow.down", .down, "Down arrow", symbol: true)
                }
            }
            key("arrow.right", .right, "Right arrow", symbol: true)
        }
    }

    private var modifierRow: some View {
        HStack(spacing: 8) {
            ForEach(ModifierKey.allCases) { key in
                let on = modifiers.contains(key.flag)
                Button {
                    Haptics.shared.tap()
                    withAnimation(.snappy(duration: 0.2)) {
                        if on { modifiers.remove(key.flag) } else { modifiers.insert(key.flag) }
                    }
                    focusToken += 1
                } label: {
                    Text(key.symbol)
                        .font(.title3.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(on ? accent : nil)
                .glassButton(prominent: on)
                .accessibilityLabel(key.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var shortcutRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Shortcut.common) { shortcut in
                    Button {
                        Haptics.shared.tap()
                        session.send(.keysKeystroke(shortcut.keystroke))
                    } label: {
                        VStack(spacing: 1) {
                            Text(shortcut.label).font(.subheadline.weight(.semibold))
                            Text(shortcut.name).font(.caption2).foregroundStyle(palette.inkSoftColor)
                        }
                        .padding(.horizontal, 4)
                        .frame(minHeight: 44)
                    }
                    .glassButton()
                    .accessibilityLabel("\(shortcut.name), \(shortcut.spoken)")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var navigationRow: some View {
        HStack(spacing: 8) {
            if settings.leftHanded {
                arrowKeys(compact: false)
                sideKeys
            } else {
                sideKeys
                arrowKeys(compact: false)
            }
        }
        .frame(height: 96)
    }

    private func key(_ label: String, _ special: SpecialKey, _ name: String, symbol: Bool = false) -> some View {
        Button {
            Haptics.shared.tap()
            session.send(.keysKeystroke(Keystroke(key: .special(special), modifiers: modifiers)))
            if !modifiers.isEmpty { withAnimation(.snappy) { modifiers = [] } }
        } label: {
            Group {
                if symbol { Image(systemName: label).font(.body.weight(.semibold)) } else { Text(label).font(.subheadline.weight(.semibold)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .glassButton()
        .accessibilityLabel(name)
    }

    private func send(_ output: StreamingTextField.Output) {
        switch output {
        case .text(let text): session.send(.keysText(text))
        case .keystroke(let stroke): session.send(.keysKeystroke(stroke))
        }
    }
}

// MARK: - Modifiers and shortcuts

private enum ModifierKey: CaseIterable, Identifiable {
    case command, option, control, shift
    var id: Self { self }
    var flag: KeyModifiers {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }
    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }
    var name: String {
        switch self {
        case .command: "Command"
        case .option: "Option"
        case .control: "Control"
        case .shift: "Shift"
        }
    }
}

extension KeyModifiers {
    /// "⌃⌥⇧⌘" in the order macOS menus use.
    var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

private struct Shortcut: Identifiable {
    let name: String
    let character: String
    var modifiers: KeyModifiers = .command
    var id: String { name }
    var keystroke: Keystroke { Keystroke(key: .character(character), modifiers: modifiers) }
    var label: String { modifiers.symbols + character.uppercased() }
    var spoken: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }
        return (parts + [character.uppercased()]).joined(separator: " ")
    }

    static let common: [Shortcut] = [
        Shortcut(name: "Copy", character: "c"),
        Shortcut(name: "Paste", character: "v"),
        Shortcut(name: "Cut", character: "x"),
        Shortcut(name: "Undo", character: "z"),
        Shortcut(name: "Redo", character: "z", modifiers: [.command, .shift]),
        Shortcut(name: "All", character: "a"),
        Shortcut(name: "Find", character: "f"),
        Shortcut(name: "Save", character: "s"),
        Shortcut(name: "New tab", character: "t"),
        Shortcut(name: "Close", character: "w"),
    ]
}

// MARK: - Streaming field

/// A UITextView that turns every edit into messages for the Mac. It keeps a short local
/// buffer only to compute what changed; the cursor is pinned to the end so the phone and
/// the Mac never disagree about where typing goes.
struct StreamingTextField: UIViewRepresentable {
    enum Output { case text(String), keystroke(Keystroke) }

    @Binding var modifiers: KeyModifiers
    @Binding var echo: String
    var focusToken: Int
    var onOutput: (Output) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> StreamingTextView {
        let view = StreamingTextView()
        view.delegate = context.coordinator
        view.coordinator = context.coordinator
        view.autocorrectionType = .default
        view.autocapitalizationType = .sentences
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.keyboardDismissMode = .none
        view.backgroundColor = .clear
        view.textColor = .clear
        view.tintColor = .clear
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: StreamingTextView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            if !uiView.isFirstResponder { uiView.becomeFirstResponder() }
        }
    }

    static func dismantleUIView(_ uiView: StreamingTextView, coordinator: Coordinator) {
        uiView.resignFirstResponder()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: StreamingTextField
        var lastFocusToken = 0
        private var sent = ""

        init(_ parent: StreamingTextField) { self.parent = parent }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Return goes to the Mac as a key and clears the local buffer.
            if text == "\n" {
                emit(.keystroke(Keystroke(key: .special(.returnKey), modifiers: takeModifiers())))
                textView.text = ""
                sent = ""
                parent.echo = ""
                return false
            }
            // With a modifier armed, a single typed character becomes a shortcut, not text.
            if !parent.modifiers.isEmpty, text.count == 1, range.length == 0 {
                emit(.keystroke(Keystroke(key: .character(text.lowercased()), modifiers: takeModifiers())))
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            // Wait while iOS is composing (dictation in progress, marked text for some languages).
            guard textView.markedTextRange == nil else { return }
            let now = textView.text ?? ""
            let common = sent.commonPrefix(with: now)
            let deletes = sent.count - common.count
            for _ in 0..<deletes { emit(.keystroke(Keystroke(key: .special(.delete)))) }
            let added = String(now.dropFirst(common.count))
            if !added.isEmpty { emit(.text(added)) }
            sent = now
            parent.echo = now
            // Keep the buffer short; the Mac already has the text.
            if now.count > 200 {
                textView.text = ""
                sent = ""
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let end = textView.endOfDocument
            if let range = textView.selectedTextRange, range.start != end || range.end != end,
               textView.markedTextRange == nil {
                textView.selectedTextRange = textView.textRange(from: end, to: end)
            }
        }

        /// Backspace on an empty buffer still deletes on the Mac.
        func deleteOnEmpty() {
            emit(.keystroke(Keystroke(key: .special(.delete), modifiers: takeModifiers())))
        }

        private func takeModifiers() -> KeyModifiers {
            let m = parent.modifiers
            if !m.isEmpty { parent.modifiers = [] }
            return m
        }

        private func emit(_ output: Output) { parent.onOutput(output) }
    }
}

final class StreamingTextView: UITextView {
    weak var coordinator: StreamingTextField.Coordinator?

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            coordinator?.deleteOnEmpty()
        } else {
            super.deleteBackward()
        }
    }
}
