import SwiftUI
import UIKit
import GlasspadKit

/// Type on the phone, it appears on the Mac as you type. Dictation works because the text
/// is read from the field after iOS has inserted it, whichever way it got there.
///
/// Modifiers are sticky, like macOS Sticky Keys: tap once for the next key, twice to lock.
/// Arrows and delete repeat while held. The fn key swaps the shortcut row for F1 to F12,
/// brightness and volume.
struct KeysMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.verticalSizeClass) private var verticalSize
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    var media = MediaStore.shared
    private var accent: Color { AppMode.keys.accent(palette) }

    @State private var sticky = StickyModifiers()
    /// The modifiers a held, repeating key started with (repeats keep them).
    @State private var heldModifiers: KeyModifiers = []
    @State private var echo = ""
    @State private var focusToken = 0
    /// Volume and brightness already asked for but not yet confirmed by the Mac.
    @State private var sentVolume: Double?
    @State private var sentBrightness: Double?

    private var compact: Bool { verticalSize == .compact }
    private var showsFunctionRow: Bool { settings.keysShowsFunctionRow }

    var body: some View {
        Group {
            if compact {
                // Sideways the system keyboard takes most of the height: one line of echo,
                // then every key in one row, then the shortcuts (or the function keys).
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    echoLine
                    HStack(spacing: 6) {
                        if settings.leftHanded {
                            arrowRow
                            editKeys
                            modifierKeys
                        } else {
                            modifierKeys
                            editKeys
                            arrowRow
                        }
                    }
                    .frame(height: 44)
                    if showsFunctionRow { functionRow(height: 40) } else if settings.keysShowsShortcuts { shortcutRow(height: 40) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            } else {
                VStack(spacing: 8) {
                    Spacer(minLength: 64)
                    echoArea
                    HStack(spacing: 6) { modifierKeys }
                        .frame(height: 50)
                    if showsFunctionRow { functionRow(height: 46) } else if settings.keysShowsShortcuts { shortcutRow(height: 46) }
                    navigationBlock
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        // Keys are drawn like keyboard keys; past this size the labels no longer fit a key.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .background {
            // The real input field sits under everything; it owns the keyboard.
            StreamingTextField(sticky: $sticky, echo: $echo, focusToken: focusToken,
                               active: session.isConnected) { output in
                send(output)
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { focusToken += 1 }
        .overlay {
            if !session.isConnected { ModeOfflineMessage(mode: .keys).background(SurfaceBackground()) }
        }
        .onAppear {
            if showsFunctionRow { requestLevels() }
            #if DEBUG
            if DebugLaunch.demoKeysLock {
                sticky.tap(.command, at: 0)
                sticky.tap(.command, at: 0.1)
                sticky.tap(.shift, at: 5)
            }
            #endif
        }
        .onChange(of: showsFunctionRow) { _, on in if on { requestLevels() } }
        .onChange(of: session.isConnected) { _, connected in
            if !connected { sticky.clear() } else if showsFunctionRow { requestLevels() }
        }
        .onChange(of: media.state?.volume) { sentVolume = nil }
        .onChange(of: media.state?.brightness) { sentBrightness = nil }
    }

    // MARK: Pieces

    private var hint: String {
        let active = sticky.active
        if active.isEmpty { return "Typing goes straight to your Mac" }
        let locked = sticky.locked
        if locked == active { return "Locked: \(locked.symbols)" }
        return "Next key: \(active.symbols)"
    }

    private var echoArea: some View {
        VStack(spacing: 6) {
            Text(echo.isEmpty ? "Start typing" : echo)
                .font(.title2)
                .foregroundStyle(echo.isEmpty ? palette.inkSoftColor : palette.inkColor)
                .lineLimit(3)
                .truncationMode(.head)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 60)
                .contentTransition(.opacity)
                .animation(.snappy, value: echo.isEmpty)
            Text(hint)
                .font(.footnote.weight(sticky.isEmpty ? .regular : .semibold))
                .foregroundStyle(sticky.isEmpty ? palette.inkSoftColor : accent)
                .contentTransition(.numericText())
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var echoLine: some View {
        HStack(spacing: 10) {
            Text(echo.isEmpty ? "Start typing" : echo)
                .font(.body)
                .foregroundStyle(echo.isEmpty ? palette.inkSoftColor : palette.inkColor)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(hint)
                .font(.footnote.weight(sticky.isEmpty ? .regular : .semibold))
                .foregroundStyle(sticky.isEmpty ? palette.inkSoftColor : accent)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    /// Portrait: esc and tab over a wide delete, and the arrows as an inverted T, the way they
    /// sit on a Mac keyboard. Five equal columns, two rows.
    private var navigationBlock: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                if settings.leftHanded {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    key("arrow.up", .up, "Up arrow", symbol: true, repeats: true)
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    key("esc", .escape, "Escape")
                    key("tab", .tab, "Tab")
                } else {
                    key("esc", .escape, "Escape")
                    key("tab", .tab, "Tab")
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    key("arrow.up", .up, "Up arrow", symbol: true, repeats: true)
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }
            GridRow {
                if settings.leftHanded {
                    key("arrow.left", .left, "Left arrow", symbol: true, repeats: true)
                    key("arrow.down", .down, "Down arrow", symbol: true, repeats: true)
                    key("arrow.right", .right, "Right arrow", symbol: true, repeats: true)
                    key("delete.left", .delete, "Delete", symbol: true, repeats: true).gridCellColumns(2)
                } else {
                    key("delete.left", .delete, "Delete", symbol: true, repeats: true).gridCellColumns(2)
                    key("arrow.left", .left, "Left arrow", symbol: true, repeats: true)
                    key("arrow.down", .down, "Down arrow", symbol: true, repeats: true)
                    key("arrow.right", .right, "Right arrow", symbol: true, repeats: true)
                }
            }
        }
        .frame(height: 98)
    }

    @ViewBuilder private var editKeys: some View {
        key("esc", .escape, "Escape")
        key("tab", .tab, "Tab")
        key("delete.left", .delete, "Delete", symbol: true, repeats: true)
    }

    @ViewBuilder private var arrowRow: some View {
        key("arrow.left", .left, "Left arrow", symbol: true, repeats: true)
        key("arrow.up", .up, "Up arrow", symbol: true, repeats: true)
        key("arrow.down", .down, "Down arrow", symbol: true, repeats: true)
        key("arrow.right", .right, "Right arrow", symbol: true, repeats: true)
    }

    @ViewBuilder private var modifierKeys: some View {
        ForEach(ModifierKey.allCases) { key in
            let state = sticky.state(of: key.flag)
            let on = state != .off
            Button {
                Haptics.shared.tap()
                withAnimation(.snappy(duration: 0.2)) {
                    sticky.tap(key.flag, at: ProcessInfo.processInfo.systemUptime)
                }
                focusToken += 1
            } label: {
                Group {
                    if compact {
                        HStack(spacing: 3) {
                            Text(key.symbol).font(.body.weight(.medium))
                            if state == .locked { Image(systemName: "lock.fill").font(.caption2) }
                        }
                    } else {
                        VStack(spacing: 1) {
                            Text(key.symbol).font(.body.weight(.medium))
                            if state == .locked {
                                Image(systemName: "lock.fill").font(.caption2)
                                    .foregroundStyle(Color.white.opacity(0.9))
                            } else {
                                Text(key.name.lowercased()).font(.caption2)
                                    .foregroundStyle(on ? Color.white.opacity(0.85) : palette.inkSoftColor)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(KeyCapStyle(accent: on ? accent : nil))
            .accessibilityLabel(key.name)
            .accessibilityValue(state == .locked ? "Locked" : on ? "Next key" : "Off")
            .accessibilityHint("Tap for the next key. Tap twice to lock.")
            .accessibilityAddTraits(on ? .isSelected : [])
        }
        fnKey
    }

    /// Shows or hides the function keys, like holding fn on a Touch Bar Mac.
    private var fnKey: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(.snappy(duration: 0.2)) { settings.keysShowsFunctionRow.toggle() }
            focusToken += 1
        } label: {
            Group {
                if compact {
                    Text("fn").font(.body.weight(.medium))
                } else {
                    VStack(spacing: 1) {
                        Text("fn").font(.body.weight(.medium))
                        Text("F1–F12").font(.caption2)
                            .foregroundStyle(showsFunctionRow ? Color.white.opacity(0.85) : palette.inkSoftColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyCapStyle(accent: showsFunctionRow ? palette.inkSoftColor : nil))
        .accessibilityLabel("Function keys")
        .accessibilityValue(showsFunctionRow ? "Shown" : "Hidden")
        .accessibilityHint("Shows F1 to F12, brightness and volume in place of the shortcuts.")
    }

    private func shortcutRow(height: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Shortcut.common) { shortcut in
                    Button {
                        Haptics.shared.tap()
                        session.send(.keysKeystroke(shortcut.keystroke))
                    } label: {
                        HStack(spacing: 6) {
                            Text(shortcut.name).font(.subheadline.weight(.medium))
                            Text(shortcut.label).font(.caption).foregroundStyle(palette.inkSoftColor)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: height)
                    }
                    .buttonStyle(KeyCapStyle())
                    .accessibilityLabel("\(shortcut.name), \(shortcut.spoken)")
                }
            }
        }
        // Scrolls edge to edge, but starts and ends in line with the keys.
        .contentMargins(.horizontal, compact ? 16 : 12, for: .scrollContent)
        .padding(.horizontal, compact ? -16 : -12)
        .frame(height: height)
    }

    // MARK: Function row

    private static let functionKeys: [SpecialKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]

    /// F1 to F12, then the Mac's brightness and volume (the same controls Media uses). esc is
    /// already on screen.
    private func functionRow(height: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(Self.functionKeys.enumerated()), id: \.offset) { index, special in
                    key("F\(index + 1)", special, "F\(index + 1)").frame(width: 46, height: height)
                }
                Rectangle().fill(palette.lineColor).frame(width: 1, height: height * 0.6).padding(.horizontal, 4)
                    .accessibilityHidden(true)
                levelKey("sun.min", "Brightness down", enabled: media.state?.brightness != nil, height: height) { stepBrightness(-1) }
                levelKey("sun.max", "Brightness up", enabled: media.state?.brightness != nil, height: height) { stepBrightness(1) }
                levelKey("speaker.slash", "Mute", enabled: true, repeats: false, height: height) {
                    session.send(.mediaCommand(.mute))
                }
                levelKey("speaker.wave.1", "Volume down", enabled: media.state?.volume != nil, height: height) { stepVolume(-1) }
                levelKey("speaker.wave.3", "Volume up", enabled: media.state?.volume != nil, height: height) { stepVolume(1) }
            }
        }
        .contentMargins(.horizontal, compact ? 16 : 12, for: .scrollContent)
        .padding(.horizontal, compact ? -16 : -12)
        .frame(height: height)
        .transition(.opacity)
    }

    private func levelKey(_ symbol: String, _ name: String, enabled: Bool, repeats: Bool = true,
                          height: CGFloat, _ action: @escaping () -> Void) -> some View {
        RepeatingKey(name: name, repeats: repeats, action: { _ in action() }) {
            Image(systemName: symbol).font(.body.weight(.medium))
        }
        .frame(width: 48, height: height)
        .disabled(!enabled)
    }

    /// One macOS volume or brightness step is a sixteenth.
    private static let levelStep = 1.0 / 16

    private func stepVolume(_ direction: Double) {
        guard let base = sentVolume ?? media.state?.volume else { return }
        let next = Self.stepped(base, direction)
        sentVolume = next
        session.send(.mediaSetVolume(next))
    }

    private func stepBrightness(_ direction: Double) {
        guard let base = sentBrightness ?? media.state?.brightness else { return }
        let next = Self.stepped(base, direction)
        sentBrightness = next
        session.send(.mediaSetBrightness(next))
    }

    /// The next sixteenth up or down, snapping a value between steps to the grid first.
    static func stepped(_ value: Double, _ direction: Double) -> Double {
        let steps = value / levelStep
        let next = direction > 0 ? (steps + 0.001).rounded(.down) + 1 : (steps - 0.001).rounded(.up) - 1
        return min(1, max(0, next * levelStep))
    }

    /// Volume and brightness come with the Mac's media state.
    private func requestLevels() {
        guard session.isConnected, media.state?.volume == nil else { return }
        session.send(.mediaRequest)
    }

    // MARK: Keys

    @ViewBuilder
    private func key(_ label: String, _ special: SpecialKey, _ name: String, symbol: Bool = false, repeats: Bool = false) -> some View {
        RepeatingKey(name: name, repeats: repeats, action: { isRepeat in press(special, isRepeat: isRepeat) }) {
            if symbol { Image(systemName: label).font(.body.weight(.medium)) } else { Text(label).font(.callout) }
        }
    }

    /// The first press takes the sticky modifiers; repeats of a held key keep the same ones.
    private func press(_ special: SpecialKey, isRepeat: Bool) {
        if !isRepeat {
            withAnimation(.snappy) { heldModifiers = sticky.consume() }
        }
        session.send(.keysKeystroke(Keystroke(key: .special(special), modifiers: heldModifiers)))
    }

    private func send(_ output: StreamingTextField.Output) {
        switch output {
        case .text(let text): session.send(.keysText(text))
        case .keystroke(let stroke): session.send(.keysKeystroke(stroke))
        }
    }
}

/// A flat keycap that presses once on touch down and, when `repeats`, again and again while
/// held, with the system keyboard's delay and rate (`KeyRepeat.system`). VoiceOver activates it
/// once.
private struct RepeatingKey<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    let name: String
    var repeats = false
    /// Called with `true` for repeats.
    let action: (Bool) -> Void
    @ViewBuilder var label: Label

    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        label
            .foregroundStyle(palette.inkColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(pressed ? palette.raisedPressedColor : palette.raisedColor))
            .overlay(shape.strokeBorder(palette.lineColor, lineWidth: 1))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { begin() } }
                    .onEnded { _ in end() },
                including: isEnabled ? .all : .none
            )
            .onDisappear { end() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if isEnabled { action(false) } }
    }

    private func begin() {
        pressed = true
        Haptics.shared.tap()
        action(false)
        guard repeats else { return }
        let timing = KeyRepeat.system
        repeatTask = Task { @MainActor in
            var n = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(timing.delay(beforePress: n)))
                guard !Task.isCancelled else { return }
                action(true)
                n += 1
            }
        }
    }

    private func end() {
        pressed = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}

// MARK: - Modifiers and shortcuts

private enum ModifierKey: CaseIterable, Identifiable {
    // Left to right as on a Mac keyboard, with Shift last.
    case control, option, command, shift
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

    @Binding var sticky: StickyModifiers
    @Binding var echo: String
    var focusToken: Int
    /// False while there is no Mac to type to: the keyboard goes away.
    var active: Bool = true
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
        if active { DispatchQueue.main.async { view.becomeFirstResponder() } }
        return view
    }

    func updateUIView(_ uiView: StreamingTextView, context: Context) {
        context.coordinator.parent = self
        let tokenChanged = context.coordinator.lastFocusToken != focusToken
        let becameActive = active && !context.coordinator.wasActive
        context.coordinator.lastFocusToken = focusToken
        context.coordinator.wasActive = active
        if !active {
            if uiView.isFirstResponder { uiView.resignFirstResponder() }
        } else if (tokenChanged || becameActive) && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: StreamingTextView, coordinator: Coordinator) {
        uiView.resignFirstResponder()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: StreamingTextField
        var lastFocusToken = 0
        var wasActive = true
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
            if !parent.sticky.isEmpty, text.count == 1, range.length == 0 {
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

        /// The sticky modifiers for this key; latched ones let go, locked ones stay.
        private func takeModifiers() -> KeyModifiers {
            var s = parent.sticky
            guard !s.isEmpty else { return [] }
            let m = s.consume()
            parent.sticky = s
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
