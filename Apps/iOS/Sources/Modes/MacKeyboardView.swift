import GlasspadKit
import SwiftUI
import UIKit

/// The state behind Glasspad's own keyboard: modifiers, the symbols page, keys under fingers,
/// the key pop, and what was typed. Touches come from `KeyboardTouchView`; what a key sends is
/// decided by `KeyboardOutput` (GlasspadKit).
///
/// Like the iPhone keyboard, a letter goes out when the finger lifts (so a finger that lands
/// on the wrong key can slide to the right one), or as soon as another finger lands (fast
/// two-thumb typing never loses a key). Keys that repeat (Delete, the arrows, Space) go out at
/// once and repeat while held. Modifiers act on touch down: held, they apply to keys pressed
/// meanwhile; tapped, they latch for the next key or lock on a double tap.
@MainActor
@Observable
final class KeyboardController {
    var modifiers = KeyboardModifierState()
    /// The numbers and symbols page of the narrow keyboard.
    var symbols = false
    /// The last few things typed, shown above the keys.
    var echo = ""
    /// The iPhone keyboard is up instead of this one.
    var usesSystemKeyboard = false
    /// Keys under a finger, by key id, for drawing them pressed.
    private(set) var pressed: Set<String> = []
    /// The character key showing its pop.
    private(set) var popKey: String?

    @ObservationIgnored var send: (ModeMessage) -> Void = { _ in }
    @ObservationIgnored var letters: () -> KeyboardLetters = { .us }

    private struct Touch {
        var key: MacKeyboard.PlacedKey
        /// A typing key that already went out (rolled over, or one that repeats).
        var fired = false
        var repeatTask: Task<Void, Never>?
    }
    @ObservationIgnored private var touches: [ObjectIdentifier: Touch] = [:]

    /// fn is on: the top row shows F1 to F12.
    var functionKeys: Bool { modifiers.state(of: .function) != .off }

    // MARK: Touches

    func began(_ id: ObjectIdentifier, on key: MacKeyboard.PlacedKey) {
        // Another finger landed: a letter still waiting for its finger to lift goes out now.
        for (other, touch) in touches where !touch.fired && touch.key.key.kind.types {
            fire(touch.key.key.kind)
            touches[other]?.fired = true
            if popKey == touch.key.key.id { popKey = nil }
        }
        Haptics.shared.tap()
        var touch = Touch(key: key)
        switch key.key.kind {
        case .modifier(let m):
            withAnimation(.snappy(duration: 0.15)) { modifiers.down(m) }
        case .capsLock:
            withAnimation(.snappy(duration: 0.15)) { modifiers.toggleCapsLock() }
        case .symbols:
            withAnimation(.snappy(duration: 0.15)) { symbols.toggle() }
        case .character, .special:
            if key.key.kind.repeats {
                touch.fired = true
                touch.repeatTask = startRepeating(key.key.kind)
            }
        }
        touches[id] = touch
        pressed.insert(key.key.id)
        if case .character = key.key.kind { popKey = key.key.id }
    }

    /// A finger slid. A letter not sent yet follows it to the key it is over now.
    func moved(_ id: ObjectIdentifier, to key: MacKeyboard.PlacedKey?) {
        guard let touch = touches[id], !touch.fired, touch.key.key.kind.types,
              let key, key.key.kind.types, !key.key.kind.repeats, key.key.id != touch.key.key.id else { return }
        pressed.remove(touch.key.key.id)
        pressed.insert(key.key.id)
        touches[id]?.key = key
        if case .character = key.key.kind { popKey = key.key.id } else { popKey = nil }
    }

    func ended(_ id: ObjectIdentifier) {
        guard let touch = touches.removeValue(forKey: id) else { return }
        touch.repeatTask?.cancel()
        switch touch.key.key.kind {
        case .modifier(let m):
            withAnimation(.snappy(duration: 0.15)) { modifiers.up(m, at: ProcessInfo.processInfo.systemUptime) }
        case .character, .special:
            if !touch.fired { fire(touch.key.key.kind) }
        case .capsLock, .symbols:
            break
        }
        release(touch)
    }

    /// The system took the touches (a call, Control Center): nothing is sent, nothing latches.
    func cancelled(_ id: ObjectIdentifier) {
        guard let touch = touches.removeValue(forKey: id) else { return }
        touch.repeatTask?.cancel()
        if case .modifier = touch.key.key.kind { modifiers.releaseHeld() }
        release(touch)
    }

    private func release(_ touch: Touch) {
        // Another finger may still be on the same key (the left and right Shift share nothing,
        // but two fingers on one key do).
        if !touches.values.contains(where: { $0.key.key.id == touch.key.key.id }) { pressed.remove(touch.key.key.id) }
        if popKey == touch.key.key.id { popKey = nil }
    }

    /// VoiceOver, Switch Control and Full Keyboard Access: one press of the key.
    func activate(_ kind: KeyboardKeyKind) {
        Haptics.shared.tap()
        switch kind {
        case .modifier(let m):
            withAnimation(.snappy(duration: 0.15)) {
                modifiers.down(m)
                modifiers.up(m, at: ProcessInfo.processInfo.systemUptime)
            }
        case .capsLock: modifiers.toggleCapsLock()
        case .symbols: symbols.toggle()
        case .character, .special: fire(kind)
        }
    }

    // MARK: Sending

    /// Sends one key with the modifiers it carries now. Returns what went out, for repeats.
    @discardableResult
    private func fire(_ kind: KeyboardKeyKind) -> ModeMessage? {
        let before = modifiers
        let mods = modifiers.consume()
        if before != modifiers {
            // A latched modifier let go: animate its key back.
            let after = modifiers
            modifiers = before
            withAnimation(.snappy(duration: 0.15)) { modifiers = after }
        }
        guard let message = KeyboardOutput.message(for: kind, modifiers: mods, capsLock: modifiers.capsLock,
                                                   letters: letters()) else { return nil }
        send(message)
        echo = KeyboardOutput.echo(echo, after: message)
        return message
    }

    /// The first press now, then the Mac's own feel: a pause, then a steady stream, all with
    /// the modifiers the first press had.
    private func startRepeating(_ kind: KeyboardKeyKind) -> Task<Void, Never>? {
        guard let message = fire(kind) else { return nil }
        let timing = KeyRepeat.system
        return Task { @MainActor [weak self] in
            var n = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(timing.delay(beforePress: n)))
                guard !Task.isCancelled, let self else { return }
                self.send(message)
                self.echo = KeyboardOutput.echo(self.echo, after: message)
                n += 1
            }
        }
    }

    /// Leaving the screen or losing the Mac: nothing stays held or repeating.
    func reset() {
        for touch in touches.values { touch.repeatTask?.cancel() }
        touches = [:]
        pressed = []
        popKey = nil
        modifiers.clear()
    }

    #if DEBUG
    /// Screenshots: show a key held down with its pop.
    func debugHold(_ id: String) {
        pressed.insert(id)
        if id.hasPrefix("c") { popKey = id }
    }
    #endif
}

// MARK: - Keys

/// Glasspad's keyboard: the keys of `plan.style` drawn in `size`, with one touch surface over
/// them that matches every touch to the nearest key (`MacKeyboard.key(at:)`).
struct MacKeyboardKeys: View {
    @Environment(\.palette) private var palette
    let style: KeyboardStyle
    let size: CGSize
    var keyboard: KeyboardController
    var letters: KeyboardLetters

    var body: some View {
        let rows = MacKeyboard.rows(style, .init(symbols: keyboard.symbols && style != .wide,
                                                 functionKeys: keyboard.functionKeys))
        let placed = MacKeyboard.place(rows, in: size, gap: KeyboardPlan.gap)
        ZStack(alignment: .topLeading) {
            ForEach(placed, id: \.key.id) { p in
                KeyCapView(placed: p, style: style, keyboard: keyboard, letters: letters)
                    .frame(width: p.frame.width, height: p.frame.height)
                    .offset(x: p.frame.minX, y: p.frame.minY)
            }
            // One surface takes every touch, for multi-touch, rollover and sliding between keys.
            KeyboardTouchLayer(placed: placed, keyboard: keyboard)
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)
            if let id = keyboard.popKey, let p = placed.first(where: { $0.key.id == id }),
               case .character(let code) = p.key.kind {
                KeyPop(key: p.frame, label: KeyCapView.label(letters.cap(code), keyboard.modifiers),
                       bounds: size)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// One key, drawn like the iPhone and Mac keyboards: letters on the light caps, everything
/// else on the darker ones, a hairline shadow under each. A modifier that is on is filled with
/// the Keyboard colour; a locked one (and Caps Lock) shows a small light, like a Mac's.
private struct KeyCapView: View {
    @Environment(\.palette) private var palette
    let placed: MacKeyboard.PlacedKey
    let style: KeyboardStyle
    var keyboard: KeyboardController
    let letters: KeyboardLetters

    private var kind: KeyboardKeyKind { placed.key.kind }
    private var accent: Color { palette.tint(AppMode.keys.accent(palette)) }

    var body: some View {
        let isPressed = keyboard.pressed.contains(placed.key.id)
        let lit = lightState
        let shape = RoundedRectangle(cornerRadius: style == .wide ? 6 : 7, style: .continuous)
        ZStack {
            shape.fill(palette.inkColor.opacity(palette.isDark ? 0.5 : 0.22)).offset(y: 1)
            shape.fill(fill(pressed: isPressed, lit: lit))
            shape.strokeBorder(palette.lineColor, lineWidth: palette.isDark ? 0.5 : 0)
            label
                .foregroundStyle(lit == .on ? onInk : palette.inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 1)
            if lit == .locked || (kind == .capsLock && keyboard.modifiers.capsLock) {
                // The little light of a locked key.
                // Opposite the modifier's sign, which sits in the outer top corner.
                Circle().fill(accent)
                    .frame(width: 5, height: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placed.key.side == 0 ? .topLeading : .topTrailing)
                    .padding(6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(isModifier ? [.isButton, .isToggle] : .isKeyboardKey)
        .accessibilityAction { keyboard.activate(kind) }
    }

    private enum Lit { case off, on, locked }

    /// Modifiers: filled while on; locked ones keep the key's own colour with a light (so a
    /// locked key never looks merely "next key").
    private var lightState: Lit {
        switch kind {
        case .modifier(let m):
            switch keyboard.modifiers.state(of: m) {
            case .off: return .off
            case .latched, .held: return .on
            case .locked: return .locked
            }
        case .symbols: return .off
        default: return .off
        }
    }

    private var isModifier: Bool {
        switch kind {
        case .modifier, .capsLock: true
        default: false
        }
    }

    private var isLetterKey: Bool {
        switch kind {
        case .character: true
        case .special(.space): true
        default: false
        }
    }

    private var onInk: Color { palette.monochrome ? palette.solidColor : .white }

    private func fill(pressed: Bool, lit: Lit) -> Color {
        if lit == .on { return accent.opacity(pressed ? 0.8 : 1) }
        if isLetterKey { return pressed ? palette.raisedPressedColor : palette.raisedColor }
        // The darker keys light up while pressed, as on the iPhone.
        return pressed ? palette.raisedColor : palette.raisedPressedColor
    }

    // MARK: Labels

    /// What a character key shows: a letter in the case it will type; any other key its two
    /// characters, the one Shift gives above, like a Mac keycap.
    static func label(_ cap: KeyCap, _ m: KeyboardModifierState) -> String {
        if KeyboardOutput.isLetter(cap) { return m.capitals ? cap.shifted : cap.base }
        return m.active.contains(.shift) ? cap.shifted : cap.base
    }

    @ViewBuilder private var label: some View {
        let h = placed.frame.height
        let w = placed.frame.width
        switch kind {
        case .character(let code):
            let cap = letters.cap(code)
            if KeyboardOutput.isLetter(cap) {
                Text(Self.label(cap, keyboard.modifiers))
                    .font(.system(size: min(24, h * 0.5, w * 0.8), weight: .regular))
            } else {
                let shift = keyboard.modifiers.active.contains(.shift)
                VStack(spacing: h > 40 ? 1 : -1) {
                    Text(cap.shifted)
                        .font(.system(size: min(13, h * 0.3, w * 0.5)))
                        .foregroundStyle(shift ? palette.inkColor : palette.inkSoftColor)
                    Text(cap.base)
                        .font(.system(size: min(18, h * 0.4, w * 0.7)))
                        .foregroundStyle(shift ? palette.inkSoftColor : palette.inkColor)
                }
            }
        case .special(let s):
            special(s)
        case .modifier(let m):
            modifier(m)
        case .capsLock:
            if style == .wide { word("caps lock", leading: true) } else { symbol("capslock") }
        case .symbols:
            Text(keyboard.symbols ? "ABC" : "123").font(.system(size: min(15, w * 0.4)))
        }
    }

    @ViewBuilder private func special(_ s: SpecialKey) -> some View {
        switch s {
        case .escape: Text("esc").font(.system(size: min(15, placed.frame.width * 0.45)))
        case .tab: if style == .wide { word("tab", leading: true) } else { Text("tab").font(.system(size: min(15, placed.frame.width * 0.45))) }
        case .delete: if style == .wide { word("delete", leading: false) } else { symbol("delete.left") }
        case .returnKey: if style == .wide { word("return", leading: false) } else { symbol("return") }
        case .space: Color.clear
        case .left: arrow("left")
        case .right: arrow("right")
        case .up: arrow("up")
        case .down: arrow("down")
        default:
            // F1 to F12.
            Text(Self.fName(s)).font(.system(size: min(14, placed.frame.width * 0.42)))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// Arrows: with fn on they are Home, End, Page Up and Page Down, as on a Mac.
    private func arrow(_ direction: String) -> some View {
        Image(systemName: "arrowtriangle.\(direction).fill")
            .font(.system(size: min(11, placed.frame.height * 0.4)))
    }

    @ViewBuilder private func modifier(_ m: KeyModifiers) -> some View {
        let name = Self.modifierName(m)
        if m == .shift {
            let state = keyboard.modifiers.state(of: .shift)
            if style == .wide {
                word("shift", leading: placed.key.side == 0)
            } else {
                symbol(state == .locked || keyboard.modifiers.capsLock ? "capslock.fill" : state == .off ? "shift" : "shift.fill")
            }
        } else if m == .function {
            Text("fn").font(.system(size: min(15, placed.frame.width * 0.5)))
        } else if style == .wide && placed.frame.width >= 44 {
            // The Mac's own key: its sign in the corner, its name along the bottom.
            VStack(alignment: placed.key.side == 0 ? .trailing : .leading, spacing: 0) {
                Text(Self.modifierSign(m)).font(.system(size: 12))
                Spacer(minLength: 0)
                Text(name.lowercased()).font(.system(size: 10)).fixedSize()
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: placed.key.side == 0 ? .trailing : .leading)
        } else {
            Text(Self.modifierSign(m)).font(.system(size: min(17, placed.frame.height * 0.42)))
        }
    }

    private func word(_ text: String, leading: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.bottom, 5)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leading ? .bottomLeading : .bottomTrailing)
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: min(18, placed.frame.height * 0.42), weight: .regular))
    }

    static func modifierSign(_ m: KeyModifiers) -> String {
        if m == .command { return "⌘" }
        if m == .option { return "⌥" }
        if m == .control { return "⌃" }
        if m == .shift { return "⇧" }
        return "fn"
    }

    static func modifierName(_ m: KeyModifiers) -> String {
        if m == .command { return "Command" }
        if m == .option { return "Option" }
        if m == .control { return "Control" }
        if m == .shift { return "Shift" }
        return "Function"
    }

    static func fName(_ s: SpecialKey) -> String {
        let all: [SpecialKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
        return all.firstIndex(of: s).map { "F\($0 + 1)" } ?? s.rawValue
    }

    // MARK: Accessibility

    private var accessibilityName: String {
        switch kind {
        case .character(let code): return Self.label(letters.cap(code), keyboard.modifiers)
        case .special(let s):
            switch s {
            case .escape: return "Escape"
            case .tab: return "Tab"
            case .delete: return keyboard.functionKeys ? "Forward Delete" : "Delete"
            case .returnKey: return "Return"
            case .space: return "Space"
            case .left: return keyboard.functionKeys ? "Home" : "Left arrow"
            case .right: return keyboard.functionKeys ? "End" : "Right arrow"
            case .up: return keyboard.functionKeys ? "Page Up" : "Up arrow"
            case .down: return keyboard.functionKeys ? "Page Down" : "Down arrow"
            default: return Self.fName(s)
            }
        case .modifier(let m): return Self.modifierName(m)
        case .capsLock: return "Caps Lock"
        case .symbols: return keyboard.symbols ? "Letters" : "Numbers and symbols"
        }
    }

    private var accessibilityState: String {
        switch kind {
        case .modifier(let m):
            switch keyboard.modifiers.state(of: m) {
            case .off: return "Off"
            case .latched, .held: return "On for the next key"
            case .locked: return "Locked"
            }
        case .capsLock: return keyboard.modifiers.capsLock ? "On" : "Off"
        default: return ""
        }
    }
}

/// The magnified key above a finger, like the iPhone keyboard's: a bubble joined to the key.
private struct KeyPop: View {
    @Environment(\.palette) private var palette
    let key: CGRect
    let label: String
    let bounds: CGSize

    var body: some View {
        let width = max(key.width * 1.5, 44)
        let height = key.height * 1.05
        // Kept inside the keyboard sideways; above the top row it may rise into the strip.
        let x = min(max(key.midX - width / 2, 0), bounds.width - width)
        let bubble = CGRect(x: x, y: key.minY - height - 4, width: width, height: height)
        ZStack(alignment: .topLeading) {
            // Solid first: in the glass themes keys are see-through, a pop must not be.
            PopShape(bubble: bubble, key: key)
                .fill(palette.solidColor)
            PopShape(bubble: bubble, key: key)
                .fill(palette.raisedColor)
                .shadow(color: .black.opacity(palette.isDark ? 0.5 : 0.22), radius: 4, y: 1)
            Text(label)
                .font(.system(size: min(34, height * 0.62)))
                .foregroundStyle(palette.inkColor)
                .frame(width: bubble.width, height: bubble.height)
                .offset(x: bubble.minX, y: bubble.minY)
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
    }
}

/// The bubble, the key, and a neck between them, in one path.
private struct PopShape: Shape {
    let bubble: CGRect
    let key: CGRect

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: bubble, cornerSize: CGSize(width: 10, height: 10), style: .continuous)
        p.addRoundedRect(in: key, cornerSize: CGSize(width: 7, height: 7), style: .continuous)
        // The neck: from the bubble's lower part down to the key's top corners.
        let neckTop = bubble.maxY - 10
        p.move(to: CGPoint(x: max(bubble.minX, key.minX - 2), y: neckTop))
        p.addLine(to: CGPoint(x: min(bubble.maxX, key.maxX + 2), y: neckTop))
        p.addLine(to: CGPoint(x: key.maxX, y: key.minY + 8))
        p.addLine(to: CGPoint(x: key.minX, y: key.minY + 8))
        p.closeSubpath()
        return p
    }
}

// MARK: - Touches

/// A plain UIKit view over the keys: every touch, each finger on its own, goes to the
/// controller with the key it is on.
private struct KeyboardTouchLayer: UIViewRepresentable {
    let placed: [MacKeyboard.PlacedKey]
    var keyboard: KeyboardController

    func makeUIView(context: Context) -> KeyboardTouchView {
        let view = KeyboardTouchView()
        view.keyboard = keyboard
        view.placed = placed
        return view
    }

    func updateUIView(_ view: KeyboardTouchView, context: Context) {
        view.keyboard = keyboard
        view.placed = placed
    }

    static func dismantleUIView(_ view: KeyboardTouchView, coordinator: ()) {
        view.cancelAll()
    }
}

final class KeyboardTouchView: UIView {
    var placed: [MacKeyboard.PlacedKey] = []
    weak var keyboard: KeyboardController?
    private var live: Set<ObjectIdentifier> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func key(for touch: UITouch) -> MacKeyboard.PlacedKey? {
        MacKeyboard.key(at: touch.location(in: self), in: placed, gap: KeyboardPlan.gap)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let key = key(for: touch) else { continue }
            live.insert(ObjectIdentifier(touch))
            keyboard?.began(ObjectIdentifier(touch), on: key)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where live.contains(ObjectIdentifier(touch)) {
            keyboard?.moved(ObjectIdentifier(touch), to: key(for: touch))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where live.remove(ObjectIdentifier(touch)) != nil {
            keyboard?.ended(ObjectIdentifier(touch))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where live.remove(ObjectIdentifier(touch)) != nil {
            keyboard?.cancelled(ObjectIdentifier(touch))
        }
    }

    func cancelAll() {
        for id in live { keyboard?.cancelled(id) }
        live = []
    }
}
