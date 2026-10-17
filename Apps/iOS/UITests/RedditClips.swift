import XCTest

/// Debug only (branch feat/redditmedia): drives the real Glasspad app in the simulator for the
/// Reddit clips. The shell records the simulator screen around each test; every test prints
/// "CLIP <name> START" when the app is on screen and "CLIP <name> END" when it is done, with
/// the time since 1970, so the recording can be trimmed to exactly the clip.
final class RedditClips: XCTestCase {
    var app: XCUIApplication!

    static var icons: String { ProcessInfo.processInfo.environment["GP_ICONS"] ?? "" }

    func launch(_ args: [String], theme: String = "graphite", settle: UInt32 = 2) {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-GPDemo", Self.icons, "-GPTheme", theme, "-GPStandByTime", "9:41"] + args
        app.launch()
        sleep(settle)
    }

    func mark(_ name: String, _ what: String) {
        print(String(format: "CLIP %@ %@ %.3f", name, what, Date().timeIntervalSince1970))
    }

    func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

    func dump(_ name: String) {
        print("DUMP \(name) BEGIN")
        print(app.debugDescription)
        print("DUMP \(name) END")
    }

    func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["GP_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
    }

    func testDump2() {
        let screens: [(String, [String])] = [
            ("trackpad", ["-GPFilm", "none", "-GPMode", "trackpad"]),
            ("displays", ["-GPFilm", "none", "-GPMode", "displays", "-GPDisplaysDemo", "two"]),
            ("theme", ["-GPFilm", "none", "-GPMode", "trackpad", "-GPSettingsPage", "theme"]),
            ("keys", ["-GPFilm", "none", "-GPMode", "keys"]),
        ]
        for (name, args) in screens {
            launch(args)
            shot(name + "-a")
            dump(name)
            pause(3)
            shot(name + "-b")
        }
    }

    func testDump() {
        let screens: [(String, [String])] = [
            ("trackpad", ["-GPMode", "trackpad"]),
            ("menu", ["-GPMode", "trackpad", "-GPMenu"]),
            ("present", ["-GPMode", "present"]),
            ("remote", ["-GPMode", "remote", "-GPMediaDemo", "movie"]),
            ("media", ["-GPMode", "media", "-GPMediaDemo", "music"]),
            ("keys", ["-GPMode", "keys"]),
            ("displays", ["-GPMode", "displays", "-GPDisplaysDemo", "two"]),
            ("actions", ["-GPFilm", "v4-mail"]),
            ("theme", ["-GPMode", "trackpad", "-GPSettingsPage", "theme"]),
        ]
        for (name, args) in screens {
            launch(args)
            pause(2)
            dump(name)
        }
    }

    // MARK: Helpers for the clips

    func el(_ label: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: label).firstMatch }
    func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }
    func tap(_ label: String, then s: Double = 0.8) {
        let b = button(label)
        if b.waitForExistence(timeout: 3) { b.tap() } else { print("MISSING \(label)") }
        pause(s)
    }
    func at(_ x: Double, _ y: Double) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: x, dy: y))
    }
    /// Touches the top edge so the pill comes back, then opens the mode menu from it.
    func openMenu(from mode: String) {
        at(201, 40).tap()
        pause(0.3)
        let pill = el("\(mode) mode")
        if pill.waitForExistence(timeout: 2) { pill.tap() } else { print("MISSING pill \(mode)"); at(201, 80).tap() }
        pause(1.0)
    }
    func clip(_ name: String, _ args: [String], theme: String = "graphite", settle: UInt32 = 2, _ body: () -> Void) {
        launch(args, theme: theme, settle: settle)
        mark(name, "START")
        body()
        mark(name, "END")
        pause(0.5)
    }

    // MARK: Clips

    func testClipModes() {
        clip("modes", ["-GPFilm", "none", "-GPMode", "trackpad", "-GPMediaDemo", "music", "-GPMenu"]) {
            pause(1.2)
            tap("Keyboard", then: 1.0)
            pill("Keyboard"); tap("Media", then: 1.0)
            pill("Media"); tap("Actions", then: 1.0)
            pill("Actions"); tap("Dock", then: 1.0)
            pill("Dock"); tap("Trackpad", then: 1.5)
        }
    }

    /// Taps the pill while it still shows after a mode change (it fades after 2 s).
    func pill(_ mode: String) {
        at(201, 87).tap()
        pause(1.0)
    }

    func testClipActions() {
        clip("actions", ["-GPFilm", "v4-actions", "-GPOrientation", "portrait"], settle: 0) {
            tap("Archive", then: 0.6)
            tap("Reply", then: 0.6)
            pause(2.5) // the Mac brings Safari to the front (4.5 s after launch): the buttons follow
            tap("Show All Tabs", then: 1.0)
            tap("Split Screen", then: 1.2)
            at(201, 794).tap(); pause(1.5)
        }
    }

    func testClipRemote() {
        clip("remote", ["-GPFilm", "none", "-GPMode", "remote", "-GPMediaDemo", "movie"]) {
            pause(1)
            let surface = button("Touch surface")
            surface.swipeLeft(); pause(1.0)
            surface.swipeRight(); pause(1.0)
            surface.swipeUp(); pause(1.0)
            surface.tap(); pause(1.2)
            tap("Forward 10 seconds", then: 1.0)
            tap("Back 10 seconds", then: 1.0)
            tap("Skip Intro", then: 1.0)
            tap("Full Screen", then: 1.5)
        }
    }

    func testClipMedia() {
        clip("media", ["-GPFilm", "media", "-GPMode", "media"]) {
            pause(3.5) // the scripted scrub runs
            let volume = app.sliders["Volume"].firstMatch
            if volume.waitForExistence(timeout: 2) { volume.adjust(toNormalizedSliderPosition: 0.9); pause(1.0); volume.adjust(toNormalizedSliderPosition: 0.35); pause(1.0) }
            let bright = app.sliders["Brightness"].firstMatch
            if bright.exists { bright.adjust(toNormalizedSliderPosition: 0.5); pause(1.0) }
            tap("Shuffle", then: 1.0)
            tap("Next track", then: 1.5)
        }
    }

    func testClipPresent() {
        clip("present", ["-GPFilm", "none", "-GPMode", "present"]) {
            pause(1)
            tap("Start timer", then: 1.5)
            tap("Next slide", then: 1.6)
            tap("Next slide", then: 1.6)
            let pad = el("Laser pointer pad")
            if pad.waitForExistence(timeout: 2) {
                let a = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
                let b = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.6))
                a.press(forDuration: 0.6, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.8)
                pause(0.8)
            }
            tap("Next slide", then: 1.4)
            tap("Previous slide", then: 1.5)
        }
    }

    func testClipDisplays() {
        clip("displays", ["-GPFilm", "v4-displays", "-GPMode", "displays", "-GPDisplaysDemo", "two"], settle: 0) {
            pause(6.0) // four seconds in, the Mac moves Safari to the MacBook's display (what a drag in the map sends)
        }
    }

    func testClipArrange() {
        clip("arrange", ["-GPFilm", "none", "-GPMode", "displays", "-GPDisplaysDemo", "two", "-GPDisplaysArrange"]) {
            pause(1.0)
            // The built-in display, dragged from the left of the Studio Display to under it.
            at(100, 660).press(forDuration: 0.4, thenDragTo: at(250, 760), withVelocity: .slow, thenHoldForDuration: 0.4)
            pause(1.2)
            pause(1.0)
        }
    }

    func testClipThemes() {
        clip("themes", ["-GPFilm", "none", "-GPMode", "trackpad", "-GPSettingsPage", "theme"], theme: "graphite") {
            pause(0.8)
            for t in ["Paper", "Mono", "Glass Dark"] { tap(t, then: 0.5) }
            app.swipeUp(velocity: .fast); pause(0.6)
            for t in ["Aurora", "Midnight"] { tap(t, then: 0.5) }
            app.swipeUp(velocity: .fast); pause(0.6)
            for t in ["Grain", "Risograph", "Film"] { tap(t, then: 0.5) }
            app.swipeUp(velocity: .fast); pause(0.6)
            tap("Mono Blue", then: 1.2)
        }
    }

    func testClipTrackpad() {
        clip("trackpad", ["-GPFilm", "trackpad", "-GPOrientation", "portrait"], settle: 0) {
            pause(10.5)
        }
    }

    func testClipSplit() {
        clip("split", ["-GPFilm", "none", "-GPMode", "displays", "-GPDisplaysDemo", "two", "-GPDisplaysSplit", "leftAndRight"]) {
            pause(1.5)
            shot("split-open")
        }
    }

    func testClipKeys() {
        clip("keys", ["-GPFilm", "none", "-GPMode", "keys"]) {
            pause(0.8)
            for k in ["h", "e", "l", "l", "o"] { tap(k, then: 0.1) }
            tap("Space", then: 0.1)
            for k in ["m", "a", "c"] { tap(k, then: 0.1) }
            pause(1.0)
            tap("Return", then: 1.0)
            tap("Spotlight", then: 1.5)
        }
    }

    func testStills() {
        let set: [(String, String, [String])] = [
            ("actions-mail", "graphite", ["-GPFilm", "v4-mail", "-GPOrientation", "portrait"]),
            ("actions-safari-paper", "paper", ["-GPFilm", "v4-pinned", "-GPOrientation", "portrait"]),
            ("actions-keynote-grain", "grain", ["-GPFilm", "v4-keynote", "-GPOrientation", "portrait"]),
            ("finalcut-mono", "mono", ["-GPFilm", "v4-finalcut", "-GPOrientation", "portrait"]),
            ("media", "graphite", ["-GPFilm", "none", "-GPMode", "media", "-GPMediaDemo", "music"]),
            ("remote", "graphite", ["-GPFilm", "none", "-GPMode", "remote", "-GPMediaDemo", "movie"]),
            ("present", "graphite", ["-GPFilm", "none", "-GPMode", "present"]),
            ("keyboard", "graphite", ["-GPFilm", "none", "-GPMode", "keys", "-GPKeysEcho", "hello from my phone"]),
            ("displays", "graphite", ["-GPFilm", "none", "-GPMode", "displays", "-GPDisplaysDemo", "two"]),
            ("split", "graphite", ["-GPFilm", "none", "-GPMode", "displays", "-GPDisplaysDemo", "two", "-GPDisplaysSplit", "leftAndRight"]),
            ("dock", "paper", ["-GPFilm", "none", "-GPMode", "dock"]),
            ("themes", "graphite", ["-GPFilm", "none", "-GPMode", "trackpad", "-GPSettingsPage", "theme"]),
            ("layout-couch", "graphite", ["-GPFilm", "none", "-GPLayout", "couch", "-GPMediaDemo", "movie"]),
            ("standby", "graphite", ["-GPFilm", "none", "-GPLayoutPanes", "clock", "-GPStandByFace", "digital"]),
        ]
        for (name, theme, args) in set {
            launch(args, theme: theme)
            pause(3.5)
            shot("still-" + name)
        }
        for t in ["paper", "graphite", "mono", "grain", "glassDark", "aurora", "midnight", "risograph", "monoBlue", "film"] {
            launch(["-GPFilm", "v4-pinned", "-GPOrientation", "portrait"], theme: t)
            pause(3.5)
            shot("theme-" + t)
        }
    }

    func testStillPresent() {
        launch(["-GPFilm", "none", "-GPMode", "present"])
        tap("Reset timer", then: 0.5)
        tap("Start timer", then: 0.5)
        pause(12.5)
        tap("Pause timer", then: 1.0)
        pause(2.5)
        shot("still-present")
    }
}
