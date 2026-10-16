#if DEBUG
import Foundation
import GlasspadKit

/// Sample Mac data for simulator screenshots (`-GPDemo <folder of 256 px icons>`). Debug only.
struct DemoData {
    var icons: [String: Data] = [:]
    var dockApps: [DockApp] = []
    var catalog: [DockApp] = []
    var frontmost = "com.apple.Safari"
    var layout: DeckLayout
    var profile: ActiveProfileInfo
    var macros: [MacroSummary]

    init(iconFolder: String?) {
        var names: [String: String] = [:]
        if let folder = iconFolder,
           let data = try? Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("list.json")),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            for item in list {
                guard let id = item["id"], let png = try? Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("\(id).png")) else { continue }
                icons[id] = png
                names[id] = item["name"] ?? id
            }
        }
        let dock = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS", "com.apple.iCal", "com.apple.Notes",
                    "com.apple.reminders", "com.apple.Music", "com.apple.Photos", "com.microsoft.Word", "com.microsoft.Excel",
                    "com.microsoft.Outlook", "com.apple.dt.Xcode", "com.apple.Terminal", "com.apple.AppStore", "com.apple.systempreferences"]
        let running: Set<String> = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.microsoft.Word", "com.apple.dt.Xcode", "com.apple.Music"]
        func name(_ id: String) -> String { names[id] ?? id.split(separator: ".").last.map(String.init) ?? id }
        let shownDock = dock.filter { names[$0] != nil || iconFolder == nil }
        dockApps = shownDock.map { DockApp(bundleID: $0, name: name($0), running: running.contains($0), active: $0 == "com.apple.Safari",
                                      iconKey: "\($0)@demo", inDock: true, recent: false) }
            + ["com.figma.Desktop"].filter { names[$0] != nil }.map { DockApp(bundleID: $0, name: name($0), running: true, active: false, iconKey: "\($0)@demo", inDock: false) }
            + ["com.apple.Preview", "com.apple.TextEdit", "com.apple.Maps"].filter { names[$0] != nil }.map {
                DockApp(bundleID: $0, name: name($0), running: false, active: false, iconKey: "\($0)@demo", inDock: false, recent: true) }
        catalog = names.map { DockApp(bundleID: $0.key, name: $0.value, running: false, active: false, iconKey: "\($0.key)@demo") }

        func b(_ t: String, _ s: String, _ a: DeckAction, _ c: String, _ size: DeckButtonSize? = nil) -> DeckButton {
            DeckButton(title: t, symbol: s, action: a, color: c, size: size)
        }
        let safari = DeckPage(title: "Safari", symbol: "safari", appBundleIDs: ["com.apple.Safari"], buttons: [
            b("New Tab", "plus.square.on.square", .keystroke(Keystroke(key: .character("t"), modifiers: [.command])), "#0A84FF"),
            b("Reopen Tab", "arrow.uturn.backward", .keystroke(Keystroke(key: .character("t"), modifiers: [.command, .shift])), "#0A84FF"),
            b("Reader", "doc.plaintext", .keystroke(Keystroke(key: .character("r"), modifiers: [.command, .shift])), "#30B0C7"),
            b("Private", "hand.raised.fill", .keystroke(Keystroke(key: .character("n"), modifiers: [.command, .shift])), "#636366"),
        ])
        // What a new setup looks like: the six essentials, plus two apps the user pinned.
        let pinned = DeckPage(id: DeckIDs.mine, title: "Pinned", symbol: "pin", buttons: PinnedDeck.essentials() + [
            b("Safari", "safari", .openApp(bundleID: "com.apple.Safari"), "#0A84FF"),
            b("Word", "doc.fill", .openApp(bundleID: "com.microsoft.Word"), "#0A84FF"),
            b("GitHub", "globe", .openURL("https://github.com"), "#0A84FF"),
            b("Wikipedia", "globe", .openURL("https://en.wikipedia.org"), "#0A84FF"),
            b("Windows", "folder.fill", .folder, "#8E8E93").with(children: [
                b("Left Half", "rectangle.lefthalf.filled", .system(.windowLeft), "#0A84FF"),
                b("Right Half", "rectangle.righthalf.filled", .system(.windowRight), "#0A84FF"),
                b("Fill", "rectangle.inset.filled", .system(.windowFill), "#0A84FF"),
                b("Split Screen", "rectangle.split.2x1.fill", .system(.windowSplit), "#0A84FF"),
                b("Next Display", "display.2", .system(.windowNextDisplay), "#0A84FF"),
            ]),
        ])
        layout = DeckLayout(pages: [pinned, safari])
        func m(_ n: String, _ s: String, _ c: String, _ steps: Int) -> MacroSummary {
            MacroSummary(id: UUID(), name: n, symbol: s, color: c, stepCount: steps, usesScripts: false)
        }
        let safariMacros = [m("Close Other Tabs", "xmark.square", "#FF453A", 3), m("Pin Tab", "pin.fill", "#FF9F0A", 2),
                            m("Copy Link", "link", "#30D158", 2), m("Web Inspector", "hammer.fill", "#5E5CE6", 1)]
        macros = safariMacros + [m("Rename Files", "pencil", "#0A84FF", 9), m("Daily Standup", "person.3.fill", "#12A594", 6)]
        profile = ActiveProfileInfo(profileID: UUID(), name: "Safari", symbol: "safari", bundleID: "com.apple.Safari", macros: safariMacros)
    }
}
private extension DeckButton {
    func with(children: [DeckButton]) -> DeckButton {
        var b = self
        b.children = children
        return b
    }
}
#endif
