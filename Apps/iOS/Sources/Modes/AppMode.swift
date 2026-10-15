import SwiftUI
import GlasspadKit

/// The screens the pill switches between. Each has one SF Symbol and one accent colour.
/// By default five show: Trackpad, Keyboard, Media, Apps and Actions. Actions combines Deck,
/// Macros, Clipboard and Present; Settings can split it back into those four.
enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case trackpad, keys, media, dock, actions, deck, macros, clipboard, present

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trackpad: "Trackpad"
        case .dock: "Apps"
        case .keys: "Keyboard"
        case .actions: "Actions"
        case .media: "Media"
        case .deck: "Deck"
        case .macros: "Macros"
        case .clipboard: "Clipboard"
        case .present: "Present"
        }
    }

    var symbol: String {
        switch self {
        case .trackpad: "hand.point.up.left"
        case .dock: "square.grid.3x3.fill"
        case .actions: "bolt.fill"
        case .keys: "keyboard"
        case .media: "play.circle"
        case .deck: "square.grid.2x2"
        case .macros: "wand.and.stars"
        case .clipboard: "doc.on.clipboard"
        case .present: "play.rectangle"
        }
    }

    /// One accent per mode. Trackpad stays neutral so the surface is just paper.
    func accent(_ palette: Palette) -> Color {
        switch self {
        case .trackpad: palette.inkColor
        case .dock: Color(hex: 0x3D7BF2)
        case .actions: Color(hex: 0xE8930C)
        case .keys: Color(hex: 0x8A63E8)
        case .media: Color(hex: 0xEC4F73)
        case .deck: Color(hex: 0xE8930C)
        case .macros: Color(hex: 0x12A594)
        case .clipboard: Color(hex: 0x2E9E5B)
        case .present: Color(hex: 0xEE6A2F)
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
        case .dock: "Open and switch the Mac's apps."
        case .actions: "Buttons for the app in front, Mac controls, your macros, clipboard and presenting."
        case .deck: "Your Deck buttons on their own."
        case .macros: "Your macros on their own."
        case .clipboard: "Copy between iPhone and Mac."
        case .present: "A slide remote with timer and laser."
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
