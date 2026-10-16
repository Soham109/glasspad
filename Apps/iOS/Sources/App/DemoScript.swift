#if DEBUG
import GlasspadKit
import SwiftUI
import UIKit

/// Debug builds only: scripted scenes for the demo film (promo/), recorded from the simulator
/// with `xcrun simctl io <udid> recordVideo`. There is no Mac and no finger in the simulator, so
/// the script plays both: it injects real touches into the trackpad surface (the same path
/// UIKit touches take) and feeds the demo Mac data the way a Mac would send it.
///
///   -GPFilm trackpad   one finger glide, a tap, a three finger swipe left, half a swipe back
///   -GPFilm menu       the mode menu opens, Apps is picked, then Word becomes the front app
///   -GPFilm actions    Actions with Word in front; three seconds in, the Mac switches to Safari
///   -GPFilm media      Spotify now playing; a scrub forward
///
/// Use with `-GPDemo <icon folder>` (sample Mac data). Every scene starts 1.5 s after launch.
@MainActor @Observable
final class FilmDirector {
    static let shared = FilmDirector()
    /// True while a film scene runs: the trackpad hides its "No Mac paired" status.
    private(set) var active = false
    /// Bumped to rebuild the mode switcher, which reads `DebugLaunch.showMenuAtLaunch` on appear.
    private(set) var switcherID = 0

    private var iconFolder: String?

    func start(scene: String, iconFolder: String?) {
        active = true
        self.iconFolder = iconFolder
        if FilmV4.start(scene: scene, iconFolder: iconFolder) { return }
        PhoneSettings.shared.seenTips.formUnion(["actions.front", "actions.pinned"])
        MacSession.shared.applyDemo(Self.filmData(iconFolder: iconFolder, front: scene == "actions" ? "com.microsoft.Word" : "com.apple.Safari"))
        switch scene {
        case "trackpad": AppRouter.shared.show(.trackpad)
        case "menu": AppRouter.shared.show(.trackpad)
        case "actions": AppRouter.shared.show(.actions)
        case "media": AppRouter.shared.show(.media); feedMedia(elapsed: 41)
        default: break
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            switch scene {
            case "trackpad": await trackpadScene()
            case "menu": await menuScene()
            case "actions": await actionsScene()
            case "media": await mediaScene()
            default: break
            }
        }
    }

    // MARK: Scenes

    private func menuScene() async {
        await wait(0.3)
        DebugLaunch.showMenuAtLaunch = true
        withAnimation(.snappy) { switcherID += 1 }
        await wait(1.8)
        DebugLaunch.showMenuAtLaunch = false
        withAnimation(.snappy) { switcherID += 1 }
        AppRouter.shared.show(.dock)
        await wait(2.6)
        // The tap on Word: the Mac opens it and reports it as the app in front.
        MacSession.shared.applyDemo(Self.filmData(iconFolder: iconFolder, front: "com.microsoft.Word"))
    }

    private func actionsScene() async {
        await wait(3.0)
        // What the Mac sends when the person clicks Safari: a new front app. Nothing else.
        MacSession.shared.applyDemo(Self.filmData(iconFolder: iconFolder, front: "com.apple.Safari"))
    }

    private func mediaScene() async {
        await wait(2.0)
        // A scrub: the knob is dragged from 0:41 to 1:52 over a second, then released.
        let start = CACurrentMediaTime()
        while true {
            let t = min(1, (CACurrentMediaTime() - start) / 1.0)
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            feedMedia(elapsed: 41 + 71 * e)
            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func trackpadScene() async {
        guard let view = Self.surface() else { return }
        let w = Double(view.bounds.width), h = Double(view.bounds.height)
        let a = NSObject(), b = NSObject(), c = NSObject()
        func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }

        // One finger glides in an arc.
        await stroke(view, keys: [a], duration: 2.6) { t in
            let u = ease(t)
            let p0 = (0.22, 0.72), p1 = (0.42, 0.10), p2 = (0.80, 0.38)
            let x = (1 - u) * (1 - u) * p0.0 + 2 * (1 - u) * u * p1.0 + u * u * p2.0
            let y = (1 - u) * (1 - u) * p0.1 + 2 * (1 - u) * u * p1.1 + u * u * p2.1
            return [CGPoint(x: x * w, y: y * h)]
        }
        await wait(0.8)
        // A tap.
        await stroke(view, keys: [a], duration: 0.09) { _ in [CGPoint(x: 0.62 * w, y: 0.48 * h)] }
        await wait(1.1)
        // Three fingers to the left: the next Space follows them.
        let ys = [0.30, 0.50, 0.70], dx = [0.0, -0.035, 0.02]
        await stroke(view, keys: [a, b, c], duration: 1.2) { t in
            let x = 0.74 + (0.22 - 0.74) * ease(t)
            return (0..<3).map { CGPoint(x: (x + dx[$0]) * w, y: ys[$0] * h) }
        }
        await wait(1.3)
        // Half a swipe back, a hesitation, and let go: it settles where it was.
        await stroke(view, keys: [a, b, c], duration: 1.4) { t in
            let x = t < 0.65 ? 0.26 + 0.34 * ease(t / 0.65) : 0.60 - 0.08 * ease((t - 0.65) / 0.35)
            return (0..<3).map { CGPoint(x: (x + dx[$0]) * w, y: ys[$0] * h) }
        }
    }

    // MARK: Helpers

    private func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    /// Fingers down at `path(0)`, moved along `path(t)` at the display rate, lifted at `path(1)`.
    private func stroke(_ view: TrackpadSurfaceView, keys: [NSObject], duration: Double,
                        path: (Double) -> [CGPoint]) async {
        let start = CACurrentMediaTime()
        var first = true
        while true {
            let t = min(1, (CACurrentMediaTime() - start) / duration)
            let points = path(t)
            let phase: TouchPhase = first ? .began : (t >= 1 ? .ended : .moved)
            view.debugInject(zip(keys, points).map { ($0, $1, phase) })
            first = false
            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    private static func surface() -> TrackpadSurfaceView? {
        func find(_ v: UIView) -> TrackpadSurfaceView? {
            if let s = v as? TrackpadSurfaceView { return s }
            for sub in v.subviews { if let s = find(sub) { return s } }
            return nil
        }
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] { if let s = find(window) { return s } }
        }
        return nil
    }

    /// Now playing as the Mac would send it. The song is the film's own score.
    private func feedMedia(elapsed: Double) {
        var s = MediaState(volume: 0.62, brightness: 0.8)
        s.title = "Uplifting Electronic Indie"
        s.artist = "WinnieTheMoog"
        s.isPlaying = true
        s.playbackRate = 1
        s.duration = 167
        s.elapsed = elapsed
        s.canSeek = true
        s.sourceBundleID = "com.spotify.client"
        s.sourceName = "Spotify"
        s.artworkID = "film"
        s.artworkPNG = Self.artwork
        if let folder = iconFolder {
            s.sourceIconPNG = try? Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("com.spotify.client.png"))
        }
        MediaStore.shared.receive(s)
    }

    /// Flat cover: graphite, a paper disc, one blue bar.
    private static let artwork: Data? = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 900)).image { ctx in
        UIColor(hex: 0x141414).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 900))
        UIColor(hex: 0xF2F1EE).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 250, y: 170, width: 400, height: 400))
        UIColor(hex: 0x0A84FF).setFill(); ctx.fill(CGRect(x: 0, y: 650, width: 900, height: 70))
        UIColor(hex: 0x1A1A1A).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 395, y: 315, width: 110, height: 110))
    }.pngData()

    // MARK: Data

    /// The film's Mac: Word and Safari pages for the app in front, and a Pinned page with the
    /// everyday Mac actions and two macros.
    static func filmData(iconFolder: String?, front: String) -> DemoData {
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
        func key(_ c: String, _ m: KeyModifiers) -> DeckAction { .keystroke(Keystroke(key: .character(c), modifiers: m)) }
        let word = DeckPage(title: "Word", symbol: "doc.text", appBundleIDs: ["com.microsoft.Word"], buttons: [
            b("Bold", "bold", key("b", [.command]), "#0A84FF"),
            b("Italic", "italic", key("i", [.command]), "#0A84FF"),
            b("Comment", "text.bubble", key("a", [.command, .option]), "#30B0C7"),
            b("Track Changes", "pencil.and.outline", key("e", [.command, .shift]), "#FF9F0A"),
            b("Word Count", "number", key("g", [.command, .shift]), "#8E8E93"),
            b("Find", "magnifyingglass", key("f", [.command]), "#8E8E93"),
            b("Undo", "arrow.uturn.backward", key("z", [.command]), "#636366"),
            b("Save", "square.and.arrow.down", key("s", [.command]), "#34C759"),
        ])
        let safari = DeckPage(title: "Safari", symbol: "safari", appBundleIDs: ["com.apple.Safari"], buttons: [
            b("New Tab", "plus.square.on.square", key("t", [.command]), "#0A84FF"),
            b("Reopen Tab", "arrow.uturn.backward", key("t", [.command, .shift]), "#0A84FF"),
            b("Reader", "doc.plaintext", key("r", [.command, .shift]), "#30B0C7"),
            b("Private", "hand.raised.fill", key("n", [.command, .shift]), "#636366"),
            b("Bookmark", "bookmark.fill", key("d", [.command]), "#FF9F0A"),
            b("Find", "magnifyingglass", key("f", [.command]), "#8E8E93"),
            b("Downloads", "arrow.down.circle.fill", key("l", [.command, .option]), "#34C759"),
            b("Close Tab", "xmark.square", key("w", [.command]), "#FF453A"),
        ])
        let pinned = DeckPage(id: DeckIDs.mine, title: "Pinned", symbol: "pin", buttons: [
            b("Screenshot", "camera.viewfinder", .screenshot(DeckScreenshot(area: .fullScreen)), "#0A84FF"),
            b("Lock", "lock.fill", .system(.lockScreen), "#8E8E93"),
            b("Dark Mode", "circle.lefthalf.filled", .system(.toggleDarkMode), "#636366"),
            b("Sleep Display", "moon.fill", .system(.sleepDisplay), "#5E5CE6"),
            b("Mute", "speaker.slash.fill", .system(.mute), "#FF9F0A"),
            b("Mission Control", "rectangle.3.group", .system(.missionControl), "#30B0C7"),
        ])
        d.layout = DeckLayout(pages: [pinned, word, safari])
        func m(_ n: String, _ s: String, _ c: String, _ steps: Int) -> MacroSummary {
            MacroSummary(id: UUID(uuidString: "6D61632D-0000-4000-8000-0000000001\(String(format: "%02d", steps))")!,
                         name: n, symbol: s, color: c, stepCount: steps, usesScripts: false)
        }
        d.macros = [m("Daily Standup", "person.3.fill", "#12A594", 6), m("Rename Files", "pencil", "#0A84FF", 9)]
        d.profile = ActiveProfileInfo(profileID: nil, name: front == "com.microsoft.Word" ? "Microsoft Word" : "Safari",
                                      symbol: front == "com.microsoft.Word" ? "doc.text" : "safari", bundleID: front, macros: [])
        return d
    }
}
#endif
