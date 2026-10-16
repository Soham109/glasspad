import SwiftUI
import GlasspadKit

/// The screens the pill switches between. Each has one SF Symbol and one accent colour.
/// By default five show: Trackpad, Keyboard, Media, Dock and Actions. Actions combines Deck,
/// Macros, Clipboard and Present; Settings can split it back into those four. Remote starts
/// hidden and opens from the mode menu's tools until Settings shows it in the pill.
enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case trackpad, keys, media, dock, actions, deck, macros, clipboard, present, remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trackpad: "Trackpad"
        // Stored as "dock" since the start; the screen was called Apps for a while.
        case .dock: "Dock"
        case .keys: "Keyboard"
        case .actions: "Actions"
        case .media: "Media"
        case .deck: "Deck"
        case .macros: "Macros"
        case .clipboard: "Clipboard"
        case .present: "Present"
        case .remote: "Remote"
        }
    }

    var symbol: String {
        switch self {
        case .trackpad: "hand.point.up.left.fill"
        case .dock: "dock.rectangle"
        case .actions: "bolt.fill"
        case .keys: "keyboard.fill"
        case .media: "play.circle.fill"
        case .deck: "square.grid.2x2.fill"
        case .macros: "wand.and.stars"
        case .clipboard: "doc.on.clipboard.fill"
        case .present: "play.rectangle.fill"
        case .remote: "appletvremote.gen4.fill"
        }
    }

    /// One accent per mode. Trackpad stays neutral so the surface is just paper. The others
    /// are Apple's system colours, which already carry a light and a dark value each.
    func accent(_ palette: Palette) -> Color {
        // Mono has no colours at all: every accent is the ink.
        if palette.monochrome { return palette.inkColor }
        return switch self {
        case .trackpad: palette.inkColor
        case .dock: Color(uiColor: .systemBlue)
        case .actions, .deck: Color(uiColor: .systemOrange)
        case .keys: Color(uiColor: .systemIndigo)
        case .media: Color(uiColor: .systemPink)
        case .macros: Color(uiColor: .systemTeal)
        case .clipboard: Color(uiColor: .systemGreen)
        case .present: Color(uiColor: .systemRed)
        case .remote: Color(uiColor: .systemPurple)
        }
    }

    /// Clipboard, Present and Remote: small tools in the mode menu unless shown as modes.
    var isTool: Bool { self == .clipboard || self == .present || self == .remote }

    /// The tool's lighter symbol and spoken hint in the mode menu.
    var toolSymbol: String {
        switch self {
        case .present: "play.rectangle"
        case .remote: "appletvremote.gen4"
        default: "doc.on.clipboard"
        }
    }

    var toolHint: String {
        switch self {
        case .present: "Opens the slide remote full screen"
        case .remote: "Opens a remote for films and music, full screen"
        default: "Copies between this iPhone and your Mac"
        }
    }

    /// The screen name the Mac is told about, so it can react (for example hide the laser).
    var wireMode: GlasspadMode {
        switch self {
        case .trackpad: .trackpad
        case .dock: .dock
        case .actions: .deck
        case .keys: .keys
        case .media: .media
        case .deck: .deck
        case .macros: .macros
        case .clipboard: .clipboard
        case .present: .present
        case .remote: .remote
        }
    }
}

extension AppMode {
    /// One line for Settings and first-run tips.
    var blurb: String {
        switch self {
        case .trackpad: "Your iPhone as the Mac's trackpad."
        case .keys: "Type on the Mac, with arrows and shortcuts."
        case .media: "What is playing, volume and brightness."
        case .dock: "Your Mac's Dock: open and switch apps."
        case .actions: "Other apps, Mac controls, macros and Shortcuts."
        case .deck: "Your Deck buttons on their own."
        case .macros: "Your macros on their own."
        case .clipboard: "Copy between iPhone and Mac."
        case .present: "A slide remote with timer and laser."
        case .remote: "Watch from the couch: play, skip, volume and search."
        }
    }

    /// Modes shown in the switcher, from Settings.
    @MainActor static var visible: [AppMode] {
        PhoneSettings.shared.modeList.visible(known: allCases.map(\.rawValue)).compactMap(AppMode.init(rawValue:))
    }

    /// This mode, or the one standing in for it when it is not shown.
    @MainActor var shown: AppMode {
        AppMode(rawValue: PhoneSettings.shared.modeList.replacement(for: rawValue, known: AppMode.allCases.map(\.rawValue))) ?? .trackpad
    }
}
