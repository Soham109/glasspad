#if DEBUG
import GlasspadKit
import SwiftUI
import UIKit

/// Debug builds only: the v4 film's phone scenes (promo/scripts/v4/capture.sh records them).
/// Each scene is the real app fed the data a Mac would send, so the film shows the app as it is.
///
///   -GPFilm v4-actions    Actions, Mail in front; three seconds in, the Mac switches to Safari
///   -GPFilm v4-pinned     Actions with Safari in front (Pinned holds Split Screen, Do Not Disturb, Next Display)
///   -GPFilm v4-finalcut   Actions with Final Cut Pro in front
///   -GPFilm v4-keynote    Actions with Keynote in front
///   -GPFilm v4-layout     the same Mac (Safari in front, the film's song playing), leaving the screen as it is,
///                         for a layout opened with -GPLayout
///
/// Buttons are the Mac's own starter buttons for those apps (GlasspadMacros StarterDefinitions).
@MainActor
enum FilmV4 {
    static func start(scene: String, iconFolder: String?) -> Bool {
        let front: String
        switch scene {
        case "v4-actions": front = "com.apple.mail"
        case "v4-pinned": front = "com.apple.Safari"
        case "v4-finalcut": front = "com.apple.FinalCut"
        case "v4-keynote": front = "com.apple.iWork.Keynote"
        case "v4-layout": front = "com.apple.Safari"
        default: return false
        }
        PhoneSettings.shared.seenTips.formUnion(["actions.front", "actions.pinned"])
        MacSession.shared.applyDemo(data(iconFolder: iconFolder, front: front))
        song(elapsed: 41, iconFolder: iconFolder)
        if scene != "v4-layout" { AppRouter.shared.show(.actions) }
        if scene == "v4-actions" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4.5))
                // What the Mac sends when the person clicks Safari: a new front app. Nothing else.
                MacSession.shared.applyDemo(data(iconFolder: iconFolder, front: "com.apple.Safari"))
            }
        }
        return true
    }

    /// Now playing as the Mac would send it: the film's own score (MUSIC.md), with the same
    /// flat cover the v3 film used.
    static func song(elapsed: Double, iconFolder: String?) {
        var s = MediaState(volume: 0.62, brightness: 0.8)
        s.title = "Uplifting Electronic Indie"
        s.artist = "WinnieTheMoog"
        s.isPlaying = true
        s.playbackRate = 1
        s.duration = 167
        s.elapsed = elapsed
        s.canSeek = true
        s.sourceBundleID = "com.apple.Music"
        s.sourceName = "Music"
        s.artworkID = "film"
        s.artworkPNG = cover
        if let folder = iconFolder {
            s.sourceIconPNG = try? Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("com.apple.Music.png"))
        }
        MediaStore.shared.receive(s)
    }

    private static let cover: Data? = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 900)).image { ctx in
        UIColor(hex: 0x141414).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 900))
        UIColor(hex: 0xF2F1EE).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 250, y: 170, width: 400, height: 400))
        UIColor(hex: 0x0A84FF).setFill(); ctx.fill(CGRect(x: 0, y: 650, width: 900, height: 70))
        UIColor(hex: 0x1A1A1A).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 395, y: 315, width: 110, height: 110))
    }.pngData()

    static func data(iconFolder: String?, front: String) -> DemoData {
        var d = DemoData(iconFolder: iconFolder)
        d.frontmost = front
        d.dockApps = d.dockApps.map { app in
            var a = app
            a.active = app.bundleID == front
            if app.bundleID == front { a.running = true }
            return a
        }
        func b(_ t: String, _ s: String, _ a: DeckAction, _ c: String) -> DeckButton {
            DeckButton(title: t, symbol: s, action: a, color: c)
        }
        func key(_ c: String, _ m: KeyModifiers = []) -> DeckAction { .keystroke(Keystroke(key: .character(c), modifiers: m)) }
        func special(_ k: SpecialKey, _ m: KeyModifiers = []) -> DeckAction { .keystroke(Keystroke(key: .special(k), modifiers: m)) }
        let mail = DeckPage(title: "Mail", symbol: "envelope", appBundleIDs: ["com.apple.mail"], buttons: [
            b("Archive", "archivebox", key("a", [.control, .command]), "#0A84FF"),
            b("Reply", "arrowshape.turn.up.left", key("r", [.command]), "#0A84FF"),
            b("Mark as Unread", "envelope.badge", key("u", [.shift, .command]), "#0A84FF"),
            b("Reply All", "arrowshape.turn.up.left.2", key("r", [.shift, .command]), "#0A84FF"),
            b("Forward", "arrowshape.turn.up.right", key("f", [.shift, .command]), "#0A84FF"),
            b("New Message", "square.and.pencil", key("n", [.command]), "#0A84FF"),
        ])
        let safari = DeckPage(title: "Safari", symbol: "safari", appBundleIDs: ["com.apple.Safari"], buttons: [
            b("Reopen Closed Tab", "arrow.uturn.backward", key("t", [.shift, .command]), "#0A84FF"),
            b("Show All Tabs", "square.grid.2x2", key("\\", [.shift, .command]), "#0A84FF"),
            b("Reader", "doc.plaintext", key("r", [.shift, .command]), "#0A84FF"),
            b("Downloads", "arrow.down.circle", key("l", [.option, .command]), "#0A84FF"),
            b("Previous Tab", "chevron.left", key("[", [.shift, .command]), "#0A84FF"),
            b("Next Tab", "chevron.right", key("]", [.shift, .command]), "#0A84FF"),
        ])
        let finalCut = DeckPage(title: "Final Cut Pro", symbol: "film", appBundleIDs: ["com.apple.FinalCut"], buttons: [
            b("Blade at Playhead", "scissors", key("b", [.command]), "#BF5AF2"),
            b("Set Range Start", "arrow.right.to.line", key("i"), "#BF5AF2"),
            b("Set Range End", "arrow.left.to.line", key("o"), "#BF5AF2"),
            b("Connect Clip", "arrow.turn.right.up", key("q"), "#BF5AF2"),
            b("Add Marker", "mappin", key("m"), "#BF5AF2"),
            b("Play / Pause", "playpause.fill", special(.space), "#BF5AF2"),
        ])
        let keynote = DeckPage(title: "Keynote", symbol: "play.rectangle", appBundleIDs: ["com.apple.iWork.Keynote"], buttons: [
            b("Play Slideshow", "play.fill", key("p", [.option, .command]), "#0A84FF"),
            b("Next Slide", "chevron.right", special(.right), "#0A84FF"),
            b("Previous Slide", "chevron.left", special(.left), "#0A84FF"),
            b("Black Screen", "rectangle.fill", key("b"), "#0A84FF"),
            b("Presenter Notes", "note.text", key("p", [.shift, .command]), "#0A84FF"),
            b("Skip Slide", "eye.slash", key("h", [.shift, .command]), "#0A84FF"),
        ])
        let pinned = DeckPage(id: DeckIDs.mine, title: "Pinned", symbol: "pin", buttons: [
            b("Split Screen", "rectangle.split.2x1.fill", .system(.windowSplit), "#0A84FF"),
            b("Do Not Disturb", "moon.circle.fill", .system(.doNotDisturb), "#5E5CE6"),
            b("Next Display", "display.2", .system(.windowNextDisplay), "#0A84FF"),
            b("Keep Awake", "cup.and.saucer.fill", .system(.keepAwake), "#30B0C7"),
            b("Night Shift", "sun.horizon.fill", .system(.nightShift), "#FF9F0A"),
            b("Screenshot", "camera.viewfinder", .screenshot(DeckScreenshot(area: .fullScreen)), "#0A84FF"),
            b("GitHub", "globe", .openURL("https://github.com"), "#0A84FF"),
            b("Wikipedia", "globe", .openURL("https://en.wikipedia.org"), "#0A84FF"),
        ])
        d.layout = DeckLayout(pages: [pinned, mail, safari, finalCut, keynote])
        let names = ["com.apple.mail": ("Mail", "envelope"), "com.apple.Safari": ("Safari", "safari"),
                     "com.apple.FinalCut": ("Final Cut Pro", "film"), "com.apple.iWork.Keynote": ("Keynote", "play.rectangle")]
        let (name, symbol) = names[front] ?? ("Safari", "safari")
        d.profile = ActiveProfileInfo(profileID: nil, name: name, symbol: symbol, bundleID: front, macros: [])
        return d
    }
}
#endif
