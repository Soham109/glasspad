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
    /// PNG, `DockApp.iconPixels` square (older Macs sent 64 px). nil when the phone already
    /// has the icon for `iconKey`.
    public var iconPNG: Data?
    public var running: Bool
    /// Frontmost app.
    public var active: Bool
    /// Identifies this exact icon: bundle id plus the app's modification date. The phone caches
    /// icons by it and tells the Mac which ones it has (`dockSync`).
    public var iconKey: String?
    /// In the Mac's Dock (`persistent-apps`), as opposed to only running or recent.
    public var inDock: Bool?
    /// Recently used, not in the Dock and not running.
    public var recent: Bool?
    /// Running with its windows hidden (cmd+H).
    public var hidden: Bool?

    /// Icon size the Mac renders: 3x the largest tile the phone draws, so icons stay sharp.
    public static let iconPixels = 256

    public init(bundleID: String, name: String, iconPNG: Data? = nil, running: Bool, active: Bool,
                iconKey: String? = nil, inDock: Bool? = nil, recent: Bool? = nil, hidden: Bool? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.iconPNG = iconPNG
        self.running = running
        self.active = active
        self.iconKey = iconKey
        self.inDock = inDock
        self.recent = recent
        self.hidden = hidden
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
    /// Function keys, sent as the real F-key (like "Use F1, F2, etc. keys as standard function
    /// keys"). Added Oct 2026: a Mac build without them drops the keystroke.
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
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
/// Every field after `brightness` is newer and optional, so older phones and Macs still decode it
/// (see MediaTypes.swift).
public struct MediaState: Codable, Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    /// Artwork image (PNG or JPEG). Sent once per `artworkID` per session; the phone caches it.
    public var artworkPNG: Data?
    public var isPlaying: Bool
    public var duration: TimeInterval?
    /// Position when the Mac sent this state; the phone advances it by `playbackRate`.
    public var elapsed: TimeInterval?
    public var volume: Double?
    public var brightness: Double?
    /// Playback speed: 1 normal, 0 paused.
    public var playbackRate: Double?
    /// Identifies the artwork in `artworkPNG`, nil when there is none.
    public var artworkID: String?
    /// The app playing, e.g. com.spotify.client and "Spotify".
    public var sourceBundleID: String?
    public var sourceName: String?
    /// The playing app's icon (PNG), sent once per app per session.
    public var sourceIconPNG: Data?
    public var shuffle: Bool?
    public var repeatMode: MediaRepeatMode?
    /// False when the player cannot seek (a live stream, or no way to reach it).
    public var canSeek: Bool?
    /// Sound outputs on the Mac, the current one marked.
    public var outputs: [MediaOutput]?
    /// Why song info is missing or limited, e.g. Automation permission denied.
    public var notice: MediaNotice?

    public init(title: String? = nil, artist: String? = nil, album: String? = nil, artworkPNG: Data? = nil,
                isPlaying: Bool = false, duration: TimeInterval? = nil, elapsed: TimeInterval? = nil,
                volume: Double? = nil, brightness: Double? = nil, playbackRate: Double? = nil,
                artworkID: String? = nil, sourceBundleID: String? = nil, sourceName: String? = nil,
                sourceIconPNG: Data? = nil, shuffle: Bool? = nil, repeatMode: MediaRepeatMode? = nil,
                canSeek: Bool? = nil, outputs: [MediaOutput]? = nil, notice: MediaNotice? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkPNG = artworkPNG
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsed = elapsed
        self.volume = volume
        self.brightness = brightness
        self.playbackRate = playbackRate
        self.artworkID = artworkID
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.sourceIconPNG = sourceIconPNG
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.canSeek = canSeek
        self.outputs = outputs
        self.notice = notice
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
    /// Open a file or folder (an absolute path; `~` is the home folder).
    case openFile(path: String)
    /// Run a Glasspad macro.
    case runMacro(id: UUID)
    /// Type this text.
    case typeText(String)
    /// Take a screenshot now (see `DeckScreenshot`).
    case screenshot(DeckScreenshot)
    /// Start a screen recording, or stop and save the one running.
    case screenRecording
    /// A one-tap Mac control.
    case system(DeckSystemAction)
    /// Switch the sound output to the device with this name.
    case setAudioOutput(name: String)
    /// A folder: tapping shows the button's `children`.
    case folder
}

/// One Deck button. `symbol` is an SF Symbol name.
public struct DeckButton: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var symbol: String
    public var action: DeckAction
    /// Tile colour as `#RRGGBB`; nil uses the Deck accent.
    public var color: String?
    /// nil is `.regular`.
    public var size: DeckButtonSize?
    /// The buttons inside a folder (`action == .folder`).
    public var children: [DeckButton]?

    public init(id: UUID = UUID(), title: String, symbol: String, action: DeckAction,
                color: String? = nil, size: DeckButtonSize? = nil, children: [DeckButton]? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.action = action
        self.color = color
        self.size = size
        self.children = children
    }

    /// True when the phone must ask before running it, and the Mac wants `deckRunConfirmed`.
    public var needsConfirmation: Bool {
        if case .system(let s) = action { return s.needsConfirmation }
        return false
    }
}

/// Clipboard payload.
public enum ClipboardContent: Codable, Equatable, Sendable {
    case text(String)
    case imagePNG(Data)

    /// Largest image that fits in one control message: JSON carries it as base64 (4/3 the
    /// size), and the whole frame must stay under `GlasspadService.maxFrameLength`.
    public static let maxImageBytes = 11 << 20

    /// Largest text either side sends in one message, in UTF-8 bytes (about 2 million
    /// characters of English). Over it the sender refuses with `tooLargeMessage` instead of
    /// cutting the text: a cut paste is worse than none.
    public static let maxTextBytes = 2 << 20

    /// Size in bytes as it counts against the limits (UTF-8 for text).
    public var byteCount: Int {
        switch self {
        case .text(let s): s.utf8.count
        case .imagePNG(let d): d.count
        }
    }

    /// Text over `maxTextBytes`, said in words for the user. `holder` is "The Mac clipboard",
    /// "This text" and so on.
    public static func tooLargeMessage(bytes: Int, holder: String) -> String {
        let mb = Double(bytes) / Double(1 << 20)
        return String(format: "%@ is %.1f MB of text, more than the %d MB Glasspad sends at once. Copy a smaller part.",
                      locale: Locale(identifier: "en_US_POSIX"), holder, mb, maxTextBytes >> 20)
    }
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
    /// Phone -> Mac: like `dockRequest`, listing the icon keys the phone already has, so the
    /// Mac sends each icon once.
    case dockSync(iconKeys: [String])
    /// Phone -> Mac: quit, hide, show or reveal an app.
    case dockAppAction(bundleID: String, action: DockAppAction)
    /// Mac -> phone: how `dockOpen` went; `message` says why on failure.
    case dockOpenResult(bundleID: String, ok: Bool, message: String?)
    /// Phone -> Mac: send every installed app (for search and the Deck editor).
    case dockCatalogRequest
    /// Mac -> phone: installed apps by name, without icons (`iconKey` set).
    case dockCatalog(apps: [DockApp])
    /// Phone -> Mac: send icons for these apps (search results, Deck buttons).
    case dockIconRequest(bundleIDs: [String])
    /// Mac -> phone: icons asked for with `dockIconRequest`.
    case dockIcons(apps: [DockApp])
    /// Mac -> phone: the Mac's frontmost app changed (Deck uses it to bring app pages forward).
    case frontmostApp(bundleID: String?)
    /// Mac -> phone: whether the Mac's own Dock is hidden, and why.
    case macDockState(MacDockState)
    /// Phone -> Mac: change the hide-the-Mac-Dock switches.
    case macDockSet(MacDockState)

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
    /// Phone -> Mac: seek, shuffle, repeat or switch the sound output.
    case mediaControl(MediaControl)

    // Deck
    /// Phone -> Mac: send the Deck buttons.
    case deckRequest
    /// Mac -> phone: the configured Deck buttons in grid order.
    case deckButtons([DeckButton])
    /// Phone -> Mac: run the button with this id.
    case deckRun(id: UUID)
    /// Mac -> phone: outcome of `deckRun`; `message` is shown on failure.
    case deckResult(id: UUID, ok: Bool, message: String?)
    /// Mac -> phone: pages, folders and grid density (sent along with `deckButtons`).
    case deckLayout(DeckLayout)
    /// Phone -> Mac: the edited Deck. The Mac keeps shell buttons only if they were already there.
    case deckSave(DeckLayout)
    /// Mac -> phone: outcome of `deckSave`.
    case deckSaveResult(ok: Bool, message: String?)
    /// Phone -> Mac: run a button that needs confirmation, after the user said yes.
    case deckRunConfirmed(id: UUID)
    /// Phone -> Mac: send what the button editor can pick from.
    case deckCatalogRequest
    /// Mac -> phone: sound outputs and Shortcuts on the Mac.
    case deckCatalog(DeckCatalog)
    /// Mac -> phone: an image a button made (a screenshot), for Photos or the clipboard.
    case deckImage(id: UUID, imageData: Data, destination: DeckImageDestination)

    // Clipboard
    /// Phone -> Mac: put this on the Mac pasteboard.
    case clipboardPush(ClipboardContent)
    /// Phone -> Mac: send the Mac pasteboard back.
    case clipboardPull
    /// Mac -> phone: answer to `clipboardPull`; nil when the pasteboard has no text or image.
    case clipboardContent(ClipboardContent?)
    /// Mac -> phone: answer to `clipboardPush`. `ok` is true once the content is on the Mac
    /// pasteboard; otherwise `message` says why not, in words for the user. Macs from before
    /// this message never send it.
    case clipboardPushResult(ok: Bool, message: String?)
    /// Mac -> phone: the Mac pasteboard has something but the Mac will not send it (text over
    /// `ClipboardContent.maxTextBytes`), with the reason in words for the user. Sent just before
    /// `clipboardContent(nil)`, which is all an older phone understands.
    case clipboardPullRefused(message: String)

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
