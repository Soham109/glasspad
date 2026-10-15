import SwiftUI
import GlasspadKit

/// The screens the pill switches between. Each has one SF Symbol and one accent colour.
enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case trackpad, dock, keys, media, deck, macros, clipboard, present

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trackpad: "Trackpad"
        case .dock: "Dock"
        case .keys: "Keys"
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
        case .dock: "dock.rectangle"
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
        case .keys: .keys
        case .media: .media
        case .deck: .deck
        case .macros: .macros
        case .clipboard: .clipboard
        case .present: .present
        }
    }
}
