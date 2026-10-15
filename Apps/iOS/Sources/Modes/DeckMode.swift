import SwiftUI
import GlasspadKit

/// Deck on its own, for people who split Actions back up in Settings. Same pages, tiles and
/// editor as Actions, without the front-app page, Clipboard and Present.
struct DeckMode: View {
    var body: some View { ActionsMode(deckOnly: true) }
}

/// The last result of running a Deck button.
struct DeckOutcome: Equatable {
    let id = UUID()
    let ok: Bool
    let message: String?
}

struct DeckFailure: Equatable {
    let id = UUID()
    let message: String
}

extension DeckAction {
    var spokenHint: String {
        switch self {
        case .openApp: "Opens an app on your Mac"
        case .openURL: "Opens a link on your Mac"
        case .openFile: "Opens a file or folder on your Mac"
        case .runShortcut(let name): "Runs the shortcut \(name) on your Mac"
        case .runMacro: "Runs a macro on your Mac"
        case .keystroke: "Presses a key combination on your Mac"
        case .typeText: "Types text on your Mac"
        case .shellScript: "Runs a script on your Mac"
        case .screenshot: "Takes a screenshot on your Mac"
        case .screenRecording: "Starts or stops a screen recording on your Mac"
        case .system(let s): s.spokenHint
        case .setAudioOutput(let name): "Switches the Mac's sound to \(name)"
        case .folder: "Opens this folder"
        }
    }
}

extension DeckSystemAction {
    var spokenHint: String {
        switch self {
        case .lockScreen: "Locks your Mac"
        case .sleepDisplay: "Turns off the Mac's display"
        case .sleepMac: "Puts your Mac to sleep"
        case .toggleDarkMode: "Switches the Mac between light and dark"
        case .volumeUp: "Turns the Mac's volume up"
        case .volumeDown: "Turns the Mac's volume down"
        case .mute: "Mutes or unmutes the Mac"
        case .micMute: "Mutes or unmutes the Mac's microphone"
        case .brightnessUp: "Makes the Mac's display brighter"
        case .brightnessDown: "Makes the Mac's display dimmer"
        case .playPause: "Plays or pauses on your Mac"
        case .nextTrack: "Skips to the next track"
        case .previousTrack: "Goes back a track"
        case .showDesktop: "Shows the Mac's desktop"
        case .missionControl: "Opens Mission Control"
        case .appExpose: "Shows the front app's windows"
        case .launchpad: "Opens the Mac's Apps view"
        case .emptyTrash: "Empties the Mac's Trash after you confirm"
        case .ejectAll: "Ejects every disk"
        }
    }
}
