import Foundation

/// How the phone groups Mac controls in the Library.
public enum DeckSystemGroup: String, CaseIterable, Sendable {
    case mac, windows, sound, display, media, disks

    public var title: String {
        switch self {
        case .mac: "Mac"
        case .windows: "Windows"
        case .sound: "Sound"
        case .display: "Display"
        case .media: "Media"
        case .disks: "Disks and Trash"
        }
    }
}

/// Display details for every Mac control, so the phone lists new ones without its own table.
public extension DeckSystemAction {
    var group: DeckSystemGroup {
        switch self {
        case .lockScreen, .sleepDisplay, .sleepMac, .toggleDarkMode, .showDesktop, .missionControl, .appExpose,
             .launchpad, .doNotDisturb, .keepAwake, .notificationCenter: .mac
        case .windowLeft, .windowRight, .windowTop, .windowBottom, .windowFill, .windowCenter, .windowTopLeft,
             .windowTopRight, .windowBottomLeft, .windowBottomRight, .windowPreviousSize, .windowSplit,
             .windowNextDisplay: .windows
        case .volumeUp, .volumeDown, .mute, .micMute: .sound
        case .brightnessUp, .brightnessDown, .nightShift: .display
        case .playPause, .nextTrack, .previousTrack: .media
        case .emptyTrash, .ejectAll: .disks
        }
    }

    var title: String {
        switch self {
        case .lockScreen: "Lock Screen"
        case .sleepDisplay: "Sleep Display"
        case .sleepMac: "Sleep Mac"
        case .toggleDarkMode: "Dark Mode"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .micMute: "Mute Microphone"
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        case .playPause: "Play or Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .showDesktop: "Show Desktop"
        case .missionControl: "Mission Control"
        case .appExpose: "App Windows"
        case .launchpad: "Apps"
        case .emptyTrash: "Empty Trash"
        case .ejectAll: "Eject All"
        case .doNotDisturb: "Do Not Disturb"
        case .nightShift: "Night Shift"
        case .keepAwake: "Keep Awake"
        case .notificationCenter: "Notification Center"
        case .windowLeft: "Left Half"
        case .windowRight: "Right Half"
        case .windowTop: "Top Half"
        case .windowBottom: "Bottom Half"
        case .windowFill: "Fill"
        case .windowCenter: "Center"
        case .windowTopLeft: "Top Left Quarter"
        case .windowTopRight: "Top Right Quarter"
        case .windowBottomLeft: "Bottom Left Quarter"
        case .windowBottomRight: "Bottom Right Quarter"
        case .windowPreviousSize: "Return to Previous Size"
        case .windowSplit: "Split Screen"
        case .windowNextDisplay: "Next Display"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .lockScreen: "lock.fill"
        case .sleepDisplay: "display"
        case .sleepMac: "powersleep"
        case .toggleDarkMode: "circle.lefthalf.filled"
        case .volumeUp: "speaker.plus.fill"
        case .volumeDown: "speaker.minus.fill"
        case .mute: "speaker.slash.fill"
        case .micMute: "mic.slash.fill"
        case .brightnessUp: "sun.max.fill"
        case .brightnessDown: "sun.min.fill"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .showDesktop: "menubar.dock.rectangle"
        case .missionControl: "rectangle.3.group"
        case .appExpose: "rectangle.stack"
        case .launchpad: "square.grid.3x3"
        case .emptyTrash: "trash.fill"
        case .ejectAll: "eject.fill"
        case .doNotDisturb: "moon.fill"
        case .nightShift: "sun.horizon.fill"
        case .keepAwake: "cup.and.saucer.fill"
        case .notificationCenter: "bell.badge.fill"
        case .windowLeft: "rectangle.lefthalf.filled"
        case .windowRight: "rectangle.righthalf.filled"
        case .windowTop: "rectangle.tophalf.filled"
        case .windowBottom: "rectangle.bottomhalf.filled"
        case .windowFill: "rectangle.inset.filled"
        case .windowCenter: "rectangle.center.inset.filled"
        case .windowTopLeft: "rectangle.inset.topleft.filled"
        case .windowTopRight: "rectangle.inset.topright.filled"
        case .windowBottomLeft: "rectangle.inset.bottomleft.filled"
        case .windowBottomRight: "rectangle.inset.bottomright.filled"
        case .windowPreviousSize: "arrow.uturn.backward"
        case .windowSplit: "rectangle.split.2x1.fill"
        case .windowNextDisplay: "display.2"
        }
    }

    /// Tile colour as `#RRGGBB`.
    var color: String {
        switch group {
        // Do Not Disturb in Focus indigo, Sleep Mac in the grey of the power controls; the
        // rest, Sleep Display among them, in the Mac controls' teal.
        case .mac: self == .doNotDisturb ? "#5E5CE6" : self == .sleepMac ? "#8E8E93" : "#30B0C7"
        case .windows: "#0A84FF"
        case .sound: self == .micMute ? "#FF375F" : "#FF9F0A"
        case .display: "#FFD60A"
        case .media: "#FF375F"
        case .disks: "#8E8E93"
        }
    }

    /// One line under the title in the Library, empty when the title says it all.
    var detail: String {
        switch self {
        case .sleepMac: "Asks first"
        case .emptyTrash: "Asks first"
        case .toggleDarkMode: "Switch light and dark"
        case .appExpose: "Every window of the front app"
        case .launchpad: "The Mac's app grid"
        case .keepAwake: "Until you tap it again"
        case .windowSplit: "The two front windows side by side"
        case .windowNextDisplay: "Moves the front window to your other screen"
        default: ""
        }
    }
}
