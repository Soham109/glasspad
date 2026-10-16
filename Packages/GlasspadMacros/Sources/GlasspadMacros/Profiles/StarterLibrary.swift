import Foundation
import CryptoKit

/// Built-in profiles for popular apps. Every button is one of the app's own standard,
/// documented keyboard shortcuts, or one of Glasspad's Mac controls (window tiling, Do Not
/// Disturb), so nothing here depends on the user's setup. The first
/// `frontAppDefaultCount` (6) of each profile are what the phone shows until the user picks,
/// so each list starts with what people reach for most. All are marked `.starter` and are
/// ordinary editable items once seeded.
public enum StarterLibrary {
    /// Bump when `definitions` change, and keep the shipped list in `StarterHistory.swift`, so
    /// existing Macs get the new buttons without losing their own edits (`StarterSeeder`).
    public static let version = 2

    struct Button {
        var name: String
        var symbol: String
        var step: MacroStep
        /// nil uses the profile's colour.
        var color: String?
    }

    struct Profile {
        var key: String
        var name: String
        var symbol: String
        var color: String
        var bundleIDs: [String]
        var isFallback = false
        var buttons: [Button]
    }

    /// Stable ids so restoring starters overwrites rather than duplicates.
    static func stableID(_ text: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("glasspad.starter.\(text)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 style, name based
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func b(_ name: String, _ symbol: String, _ key: MacroKey, _ mods: KeyModifiers = []) -> Button {
        Button(name: name, symbol: symbol, step: .keystroke(KeyCombo(key, mods)))
    }
    static func b(_ name: String, _ symbol: String, _ char: Character, _ mods: KeyModifiers = []) -> Button {
        Button(name: name, symbol: symbol, step: .keystroke(KeyCombo(char, mods)))
    }

    /// A Mac control (a `DeckSystemAction` raw value), in that control's own colour, or the
    /// profile's when nil.
    static func control(_ name: String, _ symbol: String, _ id: String, _ color: String?) -> Button {
        Button(name: name, symbol: symbol, step: .macControl(id), color: color)
    }

    static let windowBlue = "#0A84FF"
    static let splitScreen = control("Split Screen", "rectangle.split.2x1.fill", "windowSplit", windowBlue)
    static let leftHalf = control("Left Half", "rectangle.lefthalf.filled", "windowLeft", windowBlue)
    static let rightHalf = control("Right Half", "rectangle.righthalf.filled", "windowRight", windowBlue)
    static let fillScreen = control("Fill Screen", "rectangle.inset.filled", "windowFill", windowBlue)
    static let centerWindow = control("Center Window", "rectangle.center.inset.filled", "windowCenter", windowBlue)
    static let nextDisplay = control("Next Display", "display.2", "windowNextDisplay", windowBlue)
    static let doNotDisturb = control("Do Not Disturb", "moon.circle.fill", "doNotDisturb", "#5E5CE6")
    static let playPause = control("Play / Pause", "playpause.fill", "playPause", nil)
    static let nextTrack = control("Next", "forward.fill", "nextTrack", nil)
    static let previousTrack = control("Previous", "backward.fill", "previousTrack", nil)

    public static let macros: [Macro] = macros(from: definitions)
    public static let profiles: [ContextProfile] = profiles(from: definitions)

    static func macros(from definitions: [Profile]) -> [Macro] {
        definitions.flatMap { p in
            p.buttons.map { btn in
                Macro(id: stableID("\(p.key).\(btn.name)"), name: btn.name, symbol: btn.symbol, color: btn.color ?? p.color,
                      steps: [btn.step], origin: .starter)
            }
        }
    }

    static func profiles(from definitions: [Profile]) -> [ContextProfile] {
        definitions.map { p in
            ContextProfile(id: stableID("profile.\(p.key)"), name: p.name, symbol: p.symbol, bundleIDs: p.bundleIDs,
                           macroIDs: p.buttons.map { stableID("\(p.key).\($0.name)") },
                           isFallback: p.isFallback, origin: .starter)
        }
    }

    /// What a given version shipped (for upgrades), nil when unknown.
    static func definitions(version v: Int) -> [Profile]? {
        switch v {
        case 1: version1
        case version: definitions
        default: nil
        }
    }
}
