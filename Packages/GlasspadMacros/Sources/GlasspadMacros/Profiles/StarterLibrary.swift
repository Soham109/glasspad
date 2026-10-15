import Foundation
import CryptoKit

/// Built-in profiles for popular apps. Every button is one of the app's own
/// standard, documented keyboard shortcuts, so nothing here depends on the
/// user's setup. All are marked `.starter` and are ordinary editable items
/// once seeded.
public enum StarterLibrary {
    struct Button {
        var name: String
        var symbol: String
        var combo: KeyCombo
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

    private static func b(_ name: String, _ symbol: String, _ key: MacroKey, _ mods: KeyModifiers = []) -> Button {
        Button(name: name, symbol: symbol, combo: KeyCombo(key, mods))
    }
    private static func b(_ name: String, _ symbol: String, _ char: Character, _ mods: KeyModifiers = []) -> Button {
        Button(name: name, symbol: symbol, combo: KeyCombo(char, mods))
    }

    static let definitions: [Profile] = [
        Profile(key: "global", name: "Everywhere", symbol: "macwindow", color: "#8E8E93", bundleIDs: [],
                isFallback: true, buttons: [
                    b("Spotlight", "magnifyingglass", .special(.space), [.command]),
                    b("Screenshot Area", "camera.viewfinder", "4", [.shift, .command]),
                    b("Screenshot Tools", "camera", "5", [.shift, .command]),
                    b("Mission Control", "rectangle.3.group", .special(.up), [.control]),
                    b("Emoji & Symbols", "face.smiling", .special(.space), [.control, .command]),
                    b("Force Quit", "xmark.octagon", .special(.escape), [.option, .command]),
                    b("Lock Screen", "lock", "q", [.control, .command]),
                ]),
        Profile(key: "safari", name: "Safari", symbol: "safari", color: "#0A84FF", bundleIDs: ["com.apple.Safari"], buttons: [
            b("New Tab", "plus.square.on.square", "t", [.command]),
            b("Reopen Closed Tab", "arrow.uturn.backward", "t", [.shift, .command]),
            b("Show All Tabs", "square.grid.2x2", "\\", [.shift, .command]),
            b("Reload", "arrow.clockwise", "r", [.command]),
            b("Reader", "doc.plaintext", "r", [.shift, .command]),
            b("Address Bar", "link", "l", [.command]),
            b("Previous Tab", "chevron.left", "[", [.shift, .command]),
            b("Next Tab", "chevron.right", "]", [.shift, .command]),
            b("Private Window", "hand.raised", "n", [.shift, .command]),
            b("Downloads", "arrow.down.circle", "l", [.option, .command]),
        ]),
        Profile(key: "finder", name: "Finder", symbol: "folder", color: "#64D2FF", bundleIDs: ["com.apple.finder"], buttons: [
            b("New Window", "macwindow.badge.plus", "n", [.command]),
            b("New Folder", "folder.badge.plus", "n", [.shift, .command]),
            b("Go to Folder", "arrow.right.circle", "g", [.shift, .command]),
            b("Get Info", "info.circle", "i", [.command]),
            b("Quick Look", "eye", .special(.space)),
            b("Hidden Files", "eye.slash", ".", [.shift, .command]),
            b("Downloads", "arrow.down.circle", "l", [.option, .command]),
            b("Move to Trash", "trash", .special(.delete), [.command]),
            b("Connect to Server", "server.rack", "k", [.command]),
            b("AirDrop", "antenna.radiowaves.left.and.right", "r", [.shift, .command]),
        ]),
        Profile(key: "xcode", name: "Xcode", symbol: "hammer", color: "#147EFB", bundleIDs: ["com.apple.dt.Xcode"], buttons: [
            b("Build", "hammer", "b", [.command]),
            b("Run", "play.fill", "r", [.command]),
            b("Stop", "stop.fill", ".", [.command]),
            b("Test", "checkmark.diamond", "u", [.command]),
            b("Clean Build Folder", "trash", "k", [.shift, .command]),
            b("Open Quickly", "magnifyingglass", "o", [.shift, .command]),
            b("Navigator", "sidebar.left", "0", [.command]),
            b("Debug Area", "rectangle.bottomthird.inset.filled", "y", [.shift, .command]),
            b("Find in Project", "doc.text.magnifyingglass", "f", [.shift, .command]),
            b("Comment Lines", "text.bubble", "/", [.command]),
        ]),
        Profile(key: "finalcut", name: "Final Cut Pro", symbol: "film", color: "#BF5AF2", bundleIDs: ["com.apple.FinalCut"], buttons: [
            b("Play / Pause", "playpause.fill", .special(.space)),
            b("Blade at Playhead", "scissors", "b", [.command]),
            b("Blade Tool", "scissors", "b"),
            b("Select Tool", "cursorarrow", "a"),
            b("Mark In", "arrow.right.to.line", "i"),
            b("Mark Out", "arrow.left.to.line", "o"),
            b("Snapping", "magnet", "n"),
            b("Zoom to Fit", "arrow.up.left.and.arrow.down.right", "z", [.shift]),
            b("Import Media", "square.and.arrow.down", "i", [.command]),
            b("Render All", "gearshape.2", "r", [.control, .shift]),
        ]),
        Profile(key: "keynote", name: "Keynote", symbol: "play.rectangle", color: "#0A84FF",
                bundleIDs: ["com.apple.iWork.Keynote"], buttons: [
                    b("Play Slideshow", "play.fill", "p", [.option, .command]),
                    b("New Slide", "plus.rectangle", "n", [.shift, .command]),
                    b("Duplicate", "plus.square.on.square", "d", [.command]),
                    b("Group", "square.on.square", "g", [.option, .command]),
                    b("Ungroup", "square.split.2x1", "g", [.option, .shift, .command]),
                    b("Inspector", "sidebar.right", "i", [.option, .command]),
                ]),
        Profile(key: "music", name: "Music", symbol: "music.note", color: "#FF375F", bundleIDs: ["com.apple.Music"], buttons: [
            b("Play / Pause", "playpause.fill", .special(.space)),
            b("Previous", "backward.fill", .special(.left), [.command]),
            b("Next", "forward.fill", .special(.right), [.command]),
            b("Volume Down", "speaker.minus", .special(.down), [.command]),
            b("Volume Up", "speaker.plus", .special(.up), [.command]),
            b("Current Song", "music.note.list", "l", [.command]),
        ]),
        Profile(key: "figma", name: "Figma", symbol: "pencil.and.outline", color: "#A259FF", bundleIDs: ["com.figma.Desktop"], buttons: [
            b("Move", "cursorarrow", "v"),
            b("Frame", "number", "f"),
            b("Rectangle", "rectangle", "r"),
            b("Text", "textformat", "t"),
            b("Pen", "pencil.tip", "p"),
            b("Comment", "bubble.left", "c"),
            b("Zoom to Fit", "arrow.up.left.and.arrow.down.right", "1", [.shift]),
            b("Group", "square.on.square", "g", [.command]),
            b("Create Component", "diamond", "k", [.option, .command]),
            b("Hide UI", "rectangle.dashed", "\\", [.command]),
        ]),
        Profile(key: "vscode", name: "VS Code", symbol: "chevron.left.forwardslash.chevron.right", color: "#007ACC",
                bundleIDs: ["com.microsoft.VSCode"], buttons: [
                    b("Command Palette", "command", "p", [.shift, .command]),
                    b("Quick Open", "doc.text.magnifyingglass", "p", [.command]),
                    b("Terminal", "terminal", "`", [.control]),
                    b("Sidebar", "sidebar.left", "b", [.command]),
                    b("Find in Files", "magnifyingglass", "f", [.shift, .command]),
                    b("Format Document", "text.alignleft", "f", [.shift, .option]),
                    b("Go to Line", "arrow.down.to.line", "g", [.control]),
                    b("Toggle Comment", "text.bubble", "/", [.command]),
                    b("Split Editor", "rectangle.split.2x1", "\\", [.command]),
                    b("Rename Symbol", "pencil", .special(.f2)),
                ]),
        Profile(key: "slack", name: "Slack", symbol: "number", color: "#4A154B", bundleIDs: ["com.tinyspeck.slackmacgap"], buttons: [
            b("Jump To", "arrow.right.circle", "k", [.command]),
            b("All Unreads", "tray.full", "a", [.shift, .command]),
            b("Threads", "bubble.left.and.bubble.right", "t", [.shift, .command]),
            b("Mentions", "at", "m", [.shift, .command]),
            b("New Message", "square.and.pencil", "n", [.command]),
            b("Set Status", "face.smiling", "y", [.shift, .command]),
            b("Mark All Read", "checkmark.circle", .special(.escape), [.shift]),
            b("Sidebar", "sidebar.left", "d", [.shift, .command]),
            b("Back", "chevron.left", "[", [.command]),
        ]),
        Profile(key: "zoom", name: "Zoom", symbol: "video", color: "#2D8CFF", bundleIDs: ["us.zoom.xos"], buttons: [
            b("Mute / Unmute", "mic.slash", "a", [.shift, .command]),
            b("Video On / Off", "video.slash", "v", [.shift, .command]),
            b("Share Screen", "rectangle.on.rectangle", "s", [.shift, .command]),
            b("Chat", "bubble.left", "h", [.shift, .command]),
            b("Participants", "person.2", "u", [.command]),
            b("Raise Hand", "hand.raised", "y", [.option]),
            b("Full Screen", "arrow.up.left.and.arrow.down.right", "f", [.shift, .command]),
            b("Leave", "phone.down", "w", [.command]),
        ]),
    ]

    public static let macros: [Macro] = definitions.flatMap { p in
        p.buttons.map { btn in
            Macro(id: stableID("\(p.key).\(btn.name)"), name: btn.name, symbol: btn.symbol, color: p.color,
                  steps: [.keystroke(btn.combo)], origin: .starter)
        }
    }

    public static let profiles: [ContextProfile] = definitions.map { p in
        ContextProfile(id: stableID("profile.\(p.key)"), name: p.name, symbol: p.symbol, bundleIDs: p.bundleIDs,
                       macroIDs: p.buttons.map { stableID("\(p.key).\($0.name)") },
                       isFallback: p.isFallback, origin: .starter)
    }
}
