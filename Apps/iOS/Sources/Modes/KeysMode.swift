import SwiftUI
import UIKit
import GlasspadKit

/// Type on the phone, it appears on the Mac as you type.
///
/// Glasspad draws its own keyboard, a Mac keyboard with the Mac's own letters
/// (`MacSession.keyboardLetters`), sized to whatever it is in: the whole screen or one pane of
/// a layout, never anything outside it (`KeyboardPlan`). Sideways on the whole screen it is a
/// full Mac keyboard. The globe key on the strip above puts the iPhone keyboard up instead, for
/// dictation, emoji and other languages; the text is read from a hidden field after iOS has
/// inserted it, whichever way it got there. In a layout, the pane then has the room above the
/// iPhone keyboard to itself until it goes down (LayoutScreen).
///
/// Modifiers work like the iPad's: tap once for the next key, twice to lock, or hold one while
/// pressing keys. fn turns the top row into F1 to F12 and the arrows into Home, End, Page Up
/// and Page Down.
struct KeysMode: View {
    @Environment(\.palette) private var palette
    @Environment(\.modeTopClearance) private var topClearance
    @Environment(\.inLayoutPane) private var inLayoutPane
    @Bindable var settings = PhoneSettings.shared
    var session = MacSession.shared
    private var accent: Color { AppMode.keys.accent(palette) }

    @State private var keyboard = KeyboardController()
    /// The modifiers a held, repeating key of the iPhone keyboard's row started with.
    @State private var heldModifiers: KeyModifiers = []
    /// The shortcut row's chips by width, the one scrolled to the front, and the one it
    /// last came to rest on (`ChipWindow`).
    @State private var chipWidths: [String: CGFloat] = [:]
    @State private var firstChip: String?
    @State private var settledChip: String?

    var body: some View {
        GeometryReader { geo in
            let top = topClearance ?? 64
            // On the whole screen with the pill along the bottom, the keys stay clear of it.
            let bottom: CGFloat = !inLayoutPane && settings.pillPosition == .bottom && !keyboard.usesSystemKeyboard ? 48 : 0
            let room = CGSize(width: max(0, geo.size.width - KeyboardPlan.edge * 2),
                              height: max(0, geo.size.height - top - bottom))
            VStack(spacing: 0) {
                Spacer(minLength: top)
                if keyboard.usesSystemKeyboard {
                    systemKeyboardAccessory(room)
                } else {
                    glasspadKeyboard(KeyboardPlan.make(width: room.width, height: room.height), room: room)
                }
                Color.clear.frame(height: bottom)
            }
            .padding(.horizontal, KeyboardPlan.edge)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Keys are drawn like keyboard keys; past this size the labels no longer fit a key.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .background {
            // The iPhone keyboard's hidden field. It is first responder only while the person
            // has asked for the iPhone keyboard, so nothing grabs the keyboard on its own.
            StreamingTextField(keyboard: keyboard, active: session.isConnected && keyboard.usesSystemKeyboard) { output in
                switch output {
                case .text(let text): session.send(.keysText(text))
                case .keystroke(let stroke): session.send(.keysKeystroke(stroke))
                }
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
        }
        .overlay {
            if !session.isConnected { ModeOfflineMessage(mode: .keys).background(SurfaceBackground()) }
        }
        .onAppear {
            // The session only, never this view: the view holds the controller in its state,
            // so capturing it here would keep every controller alive after the view is gone.
            keyboard.send = { [session] in session.send($0) }
            keyboard.letters = { [session] in session.keyboardLetters }
            #if DEBUG
            applyDebugLaunch()
            #endif
        }
        .onDisappear { keyboard.reset() }
        .onChange(of: session.isConnected) { _, connected in
            if !connected {
                keyboard.reset()
                keyboard.usesSystemKeyboard = false
            }
        }
    }

    // MARK: Glasspad keyboard

    @ViewBuilder
    private func glasspadKeyboard(_ plan: KeyboardPlan, room: CGSize) -> some View {
        if plan.echoHeight > 0 {
            echoArea(height: plan.echoHeight)
        } else {
            Spacer(minLength: 0)
        }
        switch plan.fit {
        case .tooSmall:
            HStack(spacing: 10) {
                Text("Make this pane taller to type here")
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                systemKeyboardButton
            }
            .frame(height: plan.stripHeight)
            Spacer(minLength: 0)
        case .full, .short:
            strip(plan)
                .frame(height: plan.stripHeight)
                .zIndex(0)
            MacKeyboardKeys(style: plan.style, size: CGSize(width: room.width, height: plan.keysHeight),
                            keyboard: keyboard, letters: session.keyboardLetters)
                .frame(height: plan.keysHeight)
                // The key pop may rise over the strip.
                .zIndex(1)
            Color.clear.frame(height: KeyboardPlan.edge)
        }
    }

    /// Above the keys: esc on the wide keyboard (the Mac's is on the F-key row), the shortcuts,
    /// and the iPhone keyboard key. A short pane says what a taller one would add instead.
    private func strip(_ plan: KeyboardPlan) -> some View {
        HStack(spacing: 6) {
            if plan.style == .wide {
                stripKey("esc", name: "Escape") { press(.escape) }
            }
            if plan.fit == .short {
                Text("Make this pane taller for every key")
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoftColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            } else if settings.keysShowsShortcuts {
                shortcutChips
            } else {
                Spacer(minLength: 0)
            }
            systemKeyboardButton
        }
        .padding(.bottom, KeyboardPlan.gap)
    }

    /// The globe: the iPhone keyboard, for dictation, emoji and other languages. On the iPhone
    /// keyboard's row it brings the Mac keys back.
    private var systemKeyboardButton: some View {
        stripIcon(keyboard.usesSystemKeyboard ? "keyboard" : "globe",
                  name: keyboard.usesSystemKeyboard ? "Glasspad Keyboard" : "iPhone Keyboard",
                  hint: keyboard.usesSystemKeyboard ? "Shows the Mac keys again."
                                                    : "For dictation, emoji and other languages.") {
            withAnimation(.snappy(duration: 0.25)) {
                keyboard.reset()
                keyboard.usesSystemKeyboard.toggle()
            }
        }
    }

    // MARK: iPhone keyboard

    /// What sits above the iPhone keyboard: the typed text when there is room, the shortcuts,
    /// and one row of the Mac keys it lacks.
    @ViewBuilder
    private func systemKeyboardAccessory(_ room: CGSize) -> some View {
        let rows = KeyboardPlan.stripHeightValue + KeyboardPlan.minPitch + KeyboardPlan.edge
        if room.height - rows >= KeyboardPlan.minEcho {
            echoArea(height: room.height - rows)
        } else {
            Spacer(minLength: 0)
        }
        HStack(spacing: 6) {
            if settings.keysShowsShortcuts { shortcutChips } else { Spacer(minLength: 0) }
            systemKeyboardButton
        }
        .padding(.bottom, KeyboardPlan.gap)
        .frame(height: KeyboardPlan.stripHeightValue)
        HStack(spacing: KeyboardPlan.gap) {
            modifierToggles
            key("esc", .escape, "Escape")
            key("tab", .tab, "Tab")
            key("delete.left", .delete, "Delete", symbol: true, repeats: true)
            key("arrowtriangle.left.fill", .left, "Left arrow", symbol: true, repeats: true)
            key("arrowtriangle.up.fill", .up, "Up arrow", symbol: true, repeats: true)
            key("arrowtriangle.down.fill", .down, "Down arrow", symbol: true, repeats: true)
            key("arrowtriangle.right.fill", .right, "Right arrow", symbol: true, repeats: true)
        }
        .frame(height: KeyboardPlan.minPitch - KeyboardPlan.gap)
        Color.clear.frame(height: KeyboardPlan.gap + KeyboardPlan.edge)
    }

    /// Control, Option, Command and Shift for the iPhone keyboard: tap for the next key, twice
    /// to lock.
    @ViewBuilder private var modifierToggles: some View {
        ForEach([KeyModifiers.control, .option, .command, .shift], id: \.rawValue) { m in
            let state = keyboard.modifiers.state(of: m)
            let on = state != .off
            Button {
                keyboard.activate(.modifier(m))
            } label: {
                Text(Self.sign(m))
                    .font(.system(size: 17))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        if state == .locked {
                            Circle().fill(palette.tint(accent)).frame(width: 5, height: 5).padding(5)
                        }
                    }
            }
            .buttonStyle(KeyCapStyle(accent: on && state != .locked ? accent : nil, cornerRadius: 7))
            .accessibilityLabel(Self.name(m))
            .accessibilityValue(state == .locked ? "Locked" : on ? "On for the next key" : "Off")
            .accessibilityHint("Tap for the next key. Tap twice to lock.")
        }
    }

    // MARK: Pieces

    private var hint: String {
        let active = keyboard.modifiers.active
        if active.isEmpty { return keyboard.modifiers.capsLock ? "Caps Lock is on" : "Typing goes straight to your Mac" }
        let locked = keyboard.modifiers.sticky.locked
        if locked == active { return "Locked: \(active.symbols)" }
        return "Next key: \(active.symbols)"
    }

    /// The last things typed, and what the modifiers will do.
    private func echoArea(height: CGFloat) -> some View {
        let roomy = height >= 120
        let quiet = keyboard.modifiers.isEmpty && !keyboard.modifiers.capsLock
        return VStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(keyboard.echo.isEmpty ? "Start typing" : keyboard.echo)
                .font(roomy ? .title2 : .body)
                .foregroundStyle(keyboard.echo.isEmpty ? palette.inkSoftColor : palette.inkColor)
                .lineLimit(roomy ? 3 : 1)
                .truncationMode(.head)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
                .animation(.snappy, value: keyboard.echo.isEmpty)
            Text(hint)
                .font(.footnote.weight(quiet ? .regular : .semibold))
                .foregroundStyle(quiet ? palette.inkSoftColor : palette.tint(accent))
                .lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }

    /// The shortcuts, then Clipboard. All of them in a row when they fit. Otherwise the row
    /// scrolls a chip at a time and, at rest, shows only whole chips: it ends at the last chip
    /// that fits, with the rest of the room left empty before the globe, so no chip is ever
    /// cut off under it.
    private var shortcutChips: some View {
        GeometryReader { geo in
            let room = geo.size.width - 4
            let measured = Self.chipIDs.map { chipWidths[$0] ?? 0 }
            let extra = ChipWindow.stretch(widths: measured, spacing: 6, room: room)
            ScrollView(.horizontal) {
                chipRow(extra: extra).scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition(id: $firstChip, anchor: .leading)
            .onScrollPhaseChange { _, phase in
                if phase == .idle { settledChip = firstChip }
            }
            .frame(width: ChipWindow.width(widths: measured.map { $0 + extra },
                                           from: Self.chipIDs.firstIndex(of: settledChip ?? "") ?? 0,
                                           spacing: 6, room: room))
            .animation(.snappy(duration: 0.2), value: settledChip)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private static let chipIDs = Shortcut.common.map(\.id) + [AppMode.clipboard.rawValue]

    /// `extra` widens every chip so a row that scrolls fills its first screenful exactly.
    private func chipRow(extra: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(Shortcut.common) { shortcut in
                chip(shortcut.id, shortcut.name, detail: Text(shortcut.label), extra: extra) {
                    session.send(.keysKeystroke(shortcut.keystroke))
                }
                .accessibilityHint(shortcut.spoken)
            }
            // Clipboard lives here and in the Library, not in the mode menu.
            chip(AppMode.clipboard.rawValue, AppMode.clipboard.title, detail: Text(Image(systemName: "doc.on.clipboard")), extra: extra) {
                AppRouter.shared.openTool(.clipboard)
            }
            .accessibilityHint(AppMode.clipboard.toolHint)
        }
    }

    private func chip(_ id: String, _ name: String, detail: Text, extra: CGFloat,
                      _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Text(name).font(.subheadline.weight(.medium))
                detail.font(.footnote).foregroundStyle(palette.inkSoftColor)
            }
            .padding(.horizontal, 10)
            .fixedSize()
            // Its own width, before any stretch.
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { chipWidths[id] = $0 }
            .frame(width: chipWidths[id].map { $0 + extra })
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(KeyCapStyle(cornerRadius: 9))
        .id(id)
        .accessibilityLabel(name)
    }

    private func stripKey(_ label: String, name: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Text(label).font(.system(size: 15)).frame(width: 52).frame(maxHeight: .infinity)
        }
        .buttonStyle(KeyCapStyle(cornerRadius: 9))
        .accessibilityLabel(name)
    }

    private func stripIcon(_ symbol: String, name: String, hint: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Image(systemName: symbol).font(.system(size: 17)).frame(width: 48).frame(maxHeight: .infinity)
        }
        .buttonStyle(KeyCapStyle(cornerRadius: 9))
        .accessibilityLabel(name)
        .accessibilityHint(hint)
    }

    @ViewBuilder
    private func key(_ label: String, _ special: SpecialKey, _ name: String, symbol: Bool = false, repeats: Bool = false) -> some View {
        RepeatingKey(name: name, repeats: repeats, action: { isRepeat in press(special, isRepeat: isRepeat) }) {
            if symbol {
                Image(systemName: label).font(.system(size: 13))
            } else {
                Text(label).font(.system(size: 15)).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    /// The first press takes the modifiers; repeats of a held key keep the same ones.
    private func press(_ special: SpecialKey, isRepeat: Bool = false) {
        if !isRepeat {
            withAnimation(.snappy(duration: 0.15)) { heldModifiers = keyboard.modifiers.consume() }
        }
        if let message = KeyboardOutput.message(for: .special(special), modifiers: heldModifiers, capsLock: false,
                                                letters: session.keyboardLetters) {
            session.send(message)
        }
    }

    static func sign(_ m: KeyModifiers) -> String {
        m == .command ? "⌘" : m == .option ? "⌥" : m == .control ? "⌃" : "⇧"
    }

    static func name(_ m: KeyModifiers) -> String {
        m == .command ? "Command" : m == .option ? "Option" : m == .control ? "Control" : "Shift"
    }

    #if DEBUG
    private func applyDebugLaunch() {
        let k = keyboard
        if DebugLaunch.demoKeysLock {
            k.modifiers.down(.command); k.modifiers.up(.command, at: 0)
            k.modifiers.down(.command); k.modifiers.up(.command, at: 0.1)
            k.modifiers.down(.shift); k.modifiers.up(.shift, at: 5)
        }
        if DebugLaunch.demoKeysFn { k.modifiers.down(.function); k.modifiers.up(.function, at: 0) }
        if DebugLaunch.demoKeysSymbols { k.symbols = true }
        if let id = DebugLaunch.demoKeysHold { k.debugHold(id) }
        if let text = DebugLaunch.demoKeysEcho { k.echo = text }
        if DebugLaunch.demoKeysSystem {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                k.usesSystemKeyboard = true
            }
        }
    }
    #endif
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
    /// Resets when the touch ends in any way, including a cancel (a call, Control Center, the
    /// app leaving), which `onEnded` never hears about. Otherwise a held key would repeat on.
    @GestureState private var touching = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                    .updating($touching) { _, touching, _ in touching = true }
                    .onChanged { _ in if !pressed { begin() } }
                    .onEnded { _ in end() },
                including: isEnabled ? .all : .none
            )
            .onChange(of: touching) { _, down in if !down { end() } }
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

// MARK: - Shortcuts

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
    let key: Key
    var modifiers: KeyModifiers = .command
    var id: String { name }
    var keystroke: Keystroke { Keystroke(key: key, modifiers: modifiers) }
    /// "⌘C", "⌘Space", the way macOS menus write them.
    var label: String {
        switch key {
        case .character(let c): modifiers.symbols + c.uppercased()
        case .special(.space): modifiers.symbols + "Space"
        case .special(.tab): modifiers.symbols + "Tab"
        case .special(let s): modifiers.symbols + s.rawValue
        }
    }
    var spoken: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }
        switch key {
        case .character(let c): parts.append(c.uppercased())
        case .special(.space): parts.append("Space")
        case .special(.tab): parts.append("Tab")
        case .special(let s): parts.append(s.rawValue)
        }
        return parts.joined(separator: " ")
    }

    static let common: [Shortcut] = [
        Shortcut(name: "Copy", key: .character("c")),
        Shortcut(name: "Paste", key: .character("v")),
        Shortcut(name: "Undo", key: .character("z")),
        Shortcut(name: "Find", key: .character("f")),
        Shortcut(name: "Spotlight", key: .special(.space)),
        Shortcut(name: "Switch Apps", key: .special(.tab)),
    ]
}

// MARK: - Streaming field

/// A UITextView that turns every edit into messages for the Mac. It keeps a short local
/// buffer only to compute what changed; the cursor is pinned to the end so the phone and
/// the Mac never disagree about where typing goes.
struct StreamingTextField: UIViewRepresentable {
    enum Output { case text(String), keystroke(Keystroke) }

    /// Its modifiers and typed text are the Glasspad keyboard's.
    var keyboard: KeyboardController
    /// The iPhone keyboard is wanted and there is a Mac to type to. When it turns false the
    /// keyboard goes down; when the keyboard goes down any other way, Glasspad's comes back.
    var active: Bool
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
        let becameActive = active && !context.coordinator.wasActive
        context.coordinator.wasActive = active
        if !active {
            if uiView.isFirstResponder { uiView.resignFirstResponder() }
        } else if becameActive && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: StreamingTextView, coordinator: Coordinator) {
        uiView.resignFirstResponder()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: StreamingTextField
        var wasActive = false
        private var sent = ""

        init(_ parent: StreamingTextField) { self.parent = parent }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Return goes to the Mac as a key and clears the local buffer.
            if text == "\n" {
                emit(.keystroke(Keystroke(key: .special(.returnKey), modifiers: takeModifiers())))
                textView.text = ""
                sent = ""
                parent.keyboard.echo = ""
                return false
            }
            // With a modifier armed, a single typed character becomes a shortcut, not text.
            if !parent.keyboard.modifiers.isEmpty, text.count == 1, range.length == 0 {
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
            parent.keyboard.echo = now
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

        /// The keyboard went down some other way (the mode menu, another app's keyboard):
        /// Glasspad's own keyboard comes back, so nothing is left waiting for it.
        func textViewDidEndEditing(_ textView: UITextView) {
            guard parent.keyboard.usesSystemKeyboard else { return }
            withAnimation(.snappy(duration: 0.25)) { parent.keyboard.usesSystemKeyboard = false }
        }

        /// The modifiers for this key; latched ones let go, locked ones stay.
        private func takeModifiers() -> KeyModifiers {
            guard !parent.keyboard.modifiers.isEmpty else { return [] }
            return parent.keyboard.modifiers.consume()
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
