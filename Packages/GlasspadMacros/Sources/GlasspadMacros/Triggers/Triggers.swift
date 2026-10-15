import Foundation
import Carbon

/// What asked a macro to run. Reported back to the phone with progress.
public enum MacroTrigger: Equatable, Codable, Sendable {
    /// A deck button on the phone.
    case deck
    /// A named phone gesture from the gesture engine, e.g. "fourFingerTap".
    case gesture(String)
    /// A global hotkey on the Mac.
    case hotkey
    /// The Mac menu bar app or editor.
    case mac
}

public struct TriggerConflict: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case hotkey(KeyCombo)
        case gesture(String)
    }
    public var kind: Kind
    public var macroIDs: [UUID]
}

/// Maps gesture names and hotkeys to macros.
public struct TriggerRouter: Sendable {
    public let macros: [Macro]

    public init(macros: [Macro]) {
        self.macros = macros
    }

    /// The macro bound to a gesture. If several macros use the same gesture,
    /// the one on the active profile wins, so one gesture can mean different
    /// things in different apps.
    public func macro(forGesture name: String, activeProfile: ContextProfile?) -> Macro? {
        let bound = macros.filter { $0.gestureTriggers.contains(name) }
        if let profile = activeProfile {
            for id in profile.macroIDs {
                if let m = bound.first(where: { $0.id == id }) { return m }
            }
        }
        return bound.first
    }

    public func macro(forHotkey combo: KeyCombo) -> Macro? {
        macros.first { $0.hotkey == combo }
    }

    /// One binding per distinct hotkey (the first macro wins a conflict).
    public var hotkeyBindings: [(combo: KeyCombo, macroID: UUID)] {
        var seen = Set<KeyCombo>()
        var result: [(KeyCombo, UUID)] = []
        for m in macros {
            guard let k = m.hotkey, seen.insert(k).inserted else { continue }
            result.append((k, m.id))
        }
        return result
    }

    /// Hotkeys used by more than one macro (only the first can fire), and
    /// gestures used by more than one macro (resolved per profile, but worth
    /// showing in the editor).
    public var conflicts: [TriggerConflict] {
        var result: [TriggerConflict] = []
        var byHotkey: [KeyCombo: [UUID]] = [:]
        var hotkeyOrder: [KeyCombo] = []
        var byGesture: [String: [UUID]] = [:]
        var gestureOrder: [String] = []
        for m in macros {
            if let k = m.hotkey {
                if byHotkey[k] == nil { hotkeyOrder.append(k) }
                byHotkey[k, default: []].append(m.id)
            }
            for g in Set(m.gestureTriggers) {
                if byGesture[g] == nil { gestureOrder.append(g) }
                byGesture[g, default: []].append(m.id)
            }
        }
        for k in hotkeyOrder where byHotkey[k]!.count > 1 {
            result.append(TriggerConflict(kind: .hotkey(k), macroIDs: byHotkey[k]!))
        }
        for g in gestureOrder.sorted() where byGesture[g]!.count > 1 {
            result.append(TriggerConflict(kind: .gesture(g), macroIDs: byGesture[g]!))
        }
        return result
    }
}

// MARK: - Global hotkeys

/// Registers system-wide hotkeys. Hotkey callbacks arrive on the main thread.
@MainActor
public protocol HotkeyRegistering: AnyObject {
    /// Replaces every registration. Returns the combos that could not be
    /// registered (already taken by another app or the system).
    func setHotkeys(_ combos: [KeyCombo], handler: @escaping @MainActor (KeyCombo) -> Void) -> [KeyCombo]
    func removeAll()
}

/// Real hotkeys with Carbon's `RegisterEventHotKey`, the documented way to get
/// global hotkeys that needs no Accessibility or Input Monitoring permission
/// and consumes the key press so the frontmost app does not also see it.
@MainActor
public final class CarbonHotkeyCenter: HotkeyRegistering {
    private var refs: [EventHotKeyRef] = []
    private var combosByID: [UInt32: KeyCombo] = [:]
    private var handler: (@MainActor (KeyCombo) -> Void)?
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x474C_5350 // "GLSP"

    public init() {}

    static func carbonModifiers(_ m: KeyModifiers) -> UInt32 {
        var r: UInt32 = 0
        if m.contains(.command) { r |= UInt32(cmdKey) }
        if m.contains(.shift) { r |= UInt32(shiftKey) }
        if m.contains(.option) { r |= UInt32(optionKey) }
        if m.contains(.control) { r |= UInt32(controlKey) }
        return r
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            guard status == noErr else { return status }
            let center = Unmanaged<CarbonHotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let id = hotkeyID.id
            MainActor.assumeIsolated {
                if let combo = center.combosByID[id] { center.handler?(combo) }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    public func setHotkeys(_ combos: [KeyCombo], handler: @escaping @MainActor (KeyCombo) -> Void) -> [KeyCombo] {
        removeAll()
        installHandlerIfNeeded()
        self.handler = handler
        let layout = KeyboardLayoutMap.current()
        var failed: [KeyCombo] = []
        for (index, combo) in combos.enumerated() {
            guard let code = layout.keyCode(for: combo.key) else { failed.append(combo); continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(code), Self.carbonModifiers(combo.modifiers),
                                             EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                combosByID[id] = combo
            } else {
                failed.append(combo)
            }
        }
        return failed
    }

    public func removeAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
        combosByID = [:]
    }
}
