import Foundation

/// The phone's screens (SPEC section 8).
public enum GlasspadMode: String, Codable, Sendable, CaseIterable {
    case trackpad, dock, keys, media, deck, clipboard, present
    /// The Macros screen (docs/SPEC-macros.md).
    case macros
}

/// One app tile in Dock mode.
public struct DockApp: Codable, Equatable, Sendable, Hashable {
    public var bundleID: String
    public var name: String
    /// 64 px PNG. The Mac may send nil when the phone already has it cached by bundle id.
    public var iconPNG: Data?
    public var running: Bool
    /// Frontmost app.
    public var active: Bool

    public init(bundleID: String, name: String, iconPNG: Data? = nil, running: Bool, active: Bool) {
        self.bundleID = bundleID
        self.name = name
        self.iconPNG = iconPNG
        self.running = running
        self.active = active
    }
}

/// Modifier keys for a keystroke.
public struct KeyModifiers: OptionSet, Codable, Equatable, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
    public static let function = KeyModifiers(rawValue: 1 << 4)
}

/// Named non-character keys.
public enum SpecialKey: String, Codable, Sendable, CaseIterable {
    case returnKey, tab, space, delete, forwardDelete, escape
    case left, right, up, down, home, end, pageUp, pageDown
}

/// The key part of a keystroke: a named key or a single character (e.g. "c" for cmd+C).
public enum Key: Codable, Equatable, Sendable, Hashable {
    case special(SpecialKey)
    case character(String)
}

/// A key plus modifiers, e.g. cmd+shift+4.
public struct Keystroke: Codable, Equatable, Sendable, Hashable {
    public var key: Key
    public var modifiers: KeyModifiers
    public init(key: Key, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// Now-playing snapshot for Media mode. Volume and brightness are 0...1, nil when unknown.
public struct MediaState: Codable, Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var artworkPNG: Data?
    public var isPlaying: Bool
    public var duration: TimeInterval?
    public var elapsed: TimeInterval?
    public var volume: Double?
    public var brightness: Double?

    public init(title: String? = nil, artist: String? = nil, album: String? = nil, artworkPNG: Data? = nil,
                isPlaying: Bool = false, duration: TimeInterval? = nil, elapsed: TimeInterval? = nil,
                volume: Double? = nil, brightness: Double? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkPNG = artworkPNG
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsed = elapsed
        self.volume = volume
        self.brightness = brightness
    }
}

/// Transport commands for Media mode.
public enum MediaCommand: String, Codable, Sendable, CaseIterable {
    case playPause, play, pause, nextTrack, previousTrack, mute
}

/// What a Deck button does when run. Config lives on the Mac.
public enum DeckAction: Codable, Equatable, Sendable, Hashable {
    case openApp(bundleID: String)
    case openURL(String)
    case runShortcut(name: String)
    case keystroke(Keystroke)
    case shellScript(String)
}

/// One Deck button. `symbol` is an SF Symbol name.
public struct DeckButton: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var symbol: String
    public var action: DeckAction
    public init(id: UUID = UUID(), title: String, symbol: String, action: DeckAction) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.action = action
    }
}

/// Clipboard payload.
public enum ClipboardContent: Codable, Equatable, Sendable {
    case text(String)
    case imagePNG(Data)
}

/// Messages for the extra modes, carried inside `ControlMessage.mode`.
/// Direction is noted on each case. JSON with a `"t"` discriminator, like `ControlMessage`:
/// `{"t":"dockOpen","bundleID":"com.apple.Safari"}`. The older synthesized shape
/// (`{"dockOpen":{"bundleID":"com.apple.Safari"}}`) still decodes, so a phone and a Mac built a
/// few days apart keep talking. Payload types (DockApp, DeckAction, ...) keep their own encoding.
public enum ModeMessage: Codable, Equatable, Sendable {
    // General
    /// Phone -> Mac: the phone switched to this screen (e.g. hide the laser overlay on leaving Present).
    case modeSelected(GlasspadMode)

    // Dock
    /// Phone -> Mac: send the Dock app list.
    case dockRequest
    /// Mac -> phone: Dock apps followed by other running apps, in display order.
    case dockList(apps: [DockApp])
    /// Phone -> Mac: launch the app, or activate it if already running.
    case dockOpen(bundleID: String)

    // Keys
    /// Phone -> Mac: type this text as unicode key events (streamed as the user types or dictates).
    case keysText(String)
    /// Phone -> Mac: press one key with modifiers (arrows, esc, tab, cmd shortcuts).
    case keysKeystroke(Keystroke)

    // Media
    /// Phone -> Mac: send the current `mediaState` and keep sending on changes while Media is shown.
    case mediaRequest
    /// Mac -> phone: now playing, volume and brightness.
    case mediaState(MediaState)
    /// Phone -> Mac: play/pause/next/previous/mute.
    case mediaCommand(MediaCommand)
    /// Phone -> Mac: set output volume, 0...1.
    case mediaSetVolume(Double)
    /// Phone -> Mac: set main display brightness, 0...1.
    case mediaSetBrightness(Double)

    // Deck
    /// Phone -> Mac: send the Deck buttons.
    case deckRequest
    /// Mac -> phone: the configured Deck buttons in grid order.
    case deckButtons([DeckButton])
    /// Phone -> Mac: run the button with this id.
    case deckRun(id: UUID)
    /// Mac -> phone: outcome of `deckRun`; `message` is shown on failure.
    case deckResult(id: UUID, ok: Bool, message: String?)

    // Clipboard
    /// Phone -> Mac: put this on the Mac pasteboard.
    case clipboardPush(ClipboardContent)
    /// Phone -> Mac: send the Mac pasteboard back.
    case clipboardPull
    /// Mac -> phone: answer to `clipboardPull`; nil when the pasteboard has no text or image.
    case clipboardContent(ClipboardContent?)

    // Present
    /// Phone -> Mac: next slide (right arrow).
    case presentNext
    /// Phone -> Mac: previous slide (left arrow).
    case presentPrevious
    /// Phone -> Mac: show or hide the laser dot overlay.
    case presentLaser(on: Bool)
    /// Phone -> Mac: laser position, normalized 0...1 across the main display, origin top left.
    case presentLaserPosition(x: Double, y: Double)

    // Macros
    /// Both ways: Macros mode (docs/SPEC-macros.md section 6). Direction is noted on each `MacroMessage` case.
    case macro(MacroMessage)
}
