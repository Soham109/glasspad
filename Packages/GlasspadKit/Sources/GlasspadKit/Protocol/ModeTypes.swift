import Foundation

// Payload types added after the first release of the mode protocol. Every new field on an
// existing type is optional, so a phone and a Mac built a few days apart keep decoding each
// other's messages.

// MARK: - Dock

/// What the phone can ask the Mac to do with one app from Dock mode's long-press menu.
public enum DockAppAction: String, Codable, Sendable, CaseIterable {
    /// Ask the app to quit (like Quit in the Mac's Dock menu).
    case quit
    /// Hide the app's windows (cmd+H).
    case hide
    /// Show the app's windows again.
    case unhide
    /// Select the app in a Finder window.
    case revealInFinder
}

/// Whether Glasspad keeps the Mac's own Dock out of the way.
public struct MacDockState: Codable, Equatable, Sendable {
    /// The manual "Hide Mac Dock" switch.
    public var hidden: Bool
    /// "Hide the Mac Dock while Glasspad is connected".
    public var hideWhileConnected: Bool
    /// True when the Dock is hidden right now (either reason). Mac -> phone only.
    public var isHiddenNow: Bool?

    public init(hidden: Bool, hideWhileConnected: Bool, isHiddenNow: Bool? = nil) {
        self.hidden = hidden
        self.hideWhileConnected = hideWhileConnected
        self.isHiddenNow = isHiddenNow
    }
}

// MARK: - Deck

/// Where to send a Deck screenshot on the phone, besides saving it on the Mac.
public enum DeckImageDestination: String, Codable, Sendable, CaseIterable {
    case photos, clipboard
}

/// What a screenshot button captures.
public enum DeckCaptureArea: String, Codable, Sendable, CaseIterable {
    /// Every display, like cmd+shift+3.
    case fullScreen
    /// The frontmost window, without a click.
    case frontWindow
    /// A region you drag out on the Mac.
    case selection
}

/// A screenshot button: captured straight away and saved where macOS saves screenshots.
public struct DeckScreenshot: Codable, Equatable, Sendable, Hashable {
    public var area: DeckCaptureArea
    /// Also send the image to the phone.
    public var sendToPhone: DeckImageDestination?
    /// Also put it on the Mac's clipboard.
    public var copyToMacClipboard: Bool?

    public init(area: DeckCaptureArea, sendToPhone: DeckImageDestination? = nil, copyToMacClipboard: Bool? = nil) {
        self.area = area
        self.sendToPhone = sendToPhone
        self.copyToMacClipboard = copyToMacClipboard
    }
}

/// One-tap Mac controls a Deck button can run.
public enum DeckSystemAction: String, Codable, Sendable, CaseIterable {
    case lockScreen, sleepDisplay, sleepMac
    case toggleDarkMode
    case volumeUp, volumeDown, mute, micMute
    case brightnessUp, brightnessDown
    case playPause, nextTrack, previousTrack
    case showDesktop, missionControl, appExpose, launchpad
    case emptyTrash, ejectAll
    /// Turns Do Not Disturb on or off.
    case doNotDisturb
    /// Night Shift on or off.
    case nightShift
    /// Keeps the Mac awake until tapped again.
    case keepAwake
    case notificationCenter
    /// Front window to the left or right half, top or bottom half, full (not full screen), centred.
    case windowLeft, windowRight, windowTop, windowBottom, windowFill, windowCenter
    /// The two frontmost windows side by side, front one on the left.
    case windowSplit
    /// Front window to the next display, keeping its relative frame.
    case windowNextDisplay

    /// Actions that change or lose something, so the phone asks first and the Mac insists on
    /// `deckRunConfirmed`.
    public var needsConfirmation: Bool {
        switch self {
        case .emptyTrash, .sleepMac: true
        default: false
        }
    }
}

/// Size of a Deck button in grid cells.
public enum DeckButtonSize: String, Codable, Sendable, CaseIterable {
    /// One cell.
    case regular
    /// Two cells across.
    case wide
    /// Two by two.
    case large
}

/// One page of Deck buttons. A page with app bundle ids comes forward by itself while one of
/// those apps is frontmost on the Mac.
public struct DeckPage: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var symbol: String?
    public var appBundleIDs: [String]?
    public var buttons: [DeckButton]

    public init(id: UUID = UUID(), title: String, symbol: String? = nil, appBundleIDs: [String]? = nil,
                buttons: [DeckButton]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.appBundleIDs = appBundleIDs
        self.buttons = buttons
    }

    enum CodingKeys: String, CodingKey { case id, title, symbol, appBundleIDs, buttons }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        appBundleIDs = try c.decodeIfPresent([String].self, forKey: .appBundleIDs)
        buttons = try c.decodeLenientArray(DeckButton.self, forKey: .buttons)
    }
}

/// The whole Deck: pages, folders (buttons with children) and grid density.
public struct DeckLayout: Codable, Equatable, Sendable {
    public var pages: [DeckPage]
    /// Columns in portrait, 2...6. Landscape adds columns to fit.
    public var columns: Int?
    /// Set on the Mac only. The phone cannot turn shell buttons on.
    public var allowsShellCommands: Bool?

    public init(pages: [DeckPage], columns: Int? = nil, allowsShellCommands: Bool? = nil) {
        self.pages = pages
        self.columns = columns
        self.allowsShellCommands = allowsShellCommands
    }

    enum CodingKeys: String, CodingKey { case pages, columns, allowsShellCommands }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pages = try c.decodeLenientArray(DeckPage.self, forKey: .pages)
        columns = try c.decodeIfPresent(Int.self, forKey: .columns)
        allowsShellCommands = try c.decodeIfPresent(Bool.self, forKey: .allowsShellCommands)
    }

    /// Every button on every page, folders included, depth first.
    public var allButtons: [DeckButton] { pages.flatMap { $0.buttons.flattenedDeck } }

    /// The button with this id anywhere in the layout.
    public func button(id: UUID) -> DeckButton? { allButtons.first { $0.id == id } }
}

extension Array where Element == DeckButton {
    /// The buttons and, after each folder, its children (recursively).
    public var flattenedDeck: [DeckButton] {
        flatMap { [$0] + ($0.children ?? []).flattenedDeck }
    }
}

/// Things the phone's button editor offers to pick from, read on the Mac.
public struct DeckCatalog: Codable, Equatable, Sendable {
    public var audioOutputs: [String]
    public var shortcuts: [String]

    public init(audioOutputs: [String] = [], shortcuts: [String] = []) {
        self.audioOutputs = audioOutputs
        self.shortcuts = shortcuts
    }
}
