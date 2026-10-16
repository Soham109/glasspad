import AppKit
import GlasspadKit

/// Every feature the live check tries, in order. Each one goes through the code the phone's
/// buttons reach (`DeckMode.perform` or `ModeRouter.handle`), reads back what it can, and asks
/// only when the Mac cannot tell. Putting things back is the runner's job (`LiveCheckRestorer`).
@MainActor
public enum LiveCheckSteps {
    public static func all() -> [LiveCheckStep] {
        mac() + windows() + displays() + capture() + sound() + brightness() + media() + remote() + dock()
            + shortcuts() + disruptive()
    }

    // MARK: Groups

    static let macGroup = "Mac"
    static let windowsGroup = "Windows"
    static let displaysGroup = "Displays"
    static let captureGroup = "Screenshots and Recording"
    static let soundGroup = "Sound"
    static let brightnessGroup = "Brightness and Night Shift"
    static let mediaGroup = "Media"
    static let remoteGroup = "Remote"
    static let dockGroup = "Dock"
    static let shortcutsGroup = "Shortcuts"
    static let disruptiveGroup = "Lock, Sleep and Disks"

    // MARK: Mac

    static func mac() -> [LiveCheckStep] {
        [
            LiveCheckStep(id: "dark-mode", group: macGroup, title: "Dark Mode",
                          summary: "Switches the Mac between Light and Dark with the Dark Mode button, then switches it back.") { run in
                let before = run.mac.darkMode()
                let o = await run.mac.perform(.system(.toggleDarkMode))
                await run.mac.pause(1)
                let after = run.mac.darkMode()
                return LiveCheckTrial(observed: [said(o), "Appearance: \(look(before)), now \(look(after))"],
                                      verified: check(o, changed(before, after)),
                                      question: "Did the Mac switch to \(look(after ?? !(before ?? false)))?")
            },
            LiveCheckStep(id: "do-not-disturb", group: macGroup, title: "Do Not Disturb",
                          summary: "Switches Do Not Disturb through Control Center, as the button does, then switches it back. Control Center opens and closes by itself.") { run in
                let o = await run.mac.perform(.system(.doNotDisturb))
                await run.mac.pause(0.8)
                var observed = [said(o)]
                if let focus = run.mac.focusInMenuBar() { observed.append("Focus shows in the menu bar: \(focus ? "yes" : "no")") }
                let turnedOn = o.message.map { $0.hasSuffix("is on") }
                let state = turnedOn.map { $0 ? "on" : "off" } ?? "on or off"
                return LiveCheckTrial(observed: observed, verified: o.ok ? nil : false,
                                      question: "Did Do Not Disturb turn \(state)? Check Control Center.")
            },
            LiveCheckStep(id: "keep-awake", group: macGroup, title: "Keep Awake",
                          summary: "Turns Keep Awake on, checks that macOS sees it keeping the display awake, then turns it off.") { run in
                let o = await run.mac.perform(.system(.keepAwake))
                let on = run.mac.keepAwake()
                let listed = run.mac.keepAwakeAssertionListed()
                var observed = [said(o), "Keep Awake: \(on ? "on" : "off")"]
                if let listed { observed.append("macOS lists it as keeping the display awake: \(listed ? "yes" : "no")") }
                return LiveCheckTrial(observed: observed, verified: o.ok && on && listed != false)
            },
            LiveCheckStep(id: "notification-center", group: macGroup, title: "Notification Center",
                          summary: "Opens Notification Center, then closes it.") { run in
                let o = await run.mac.perform(.system(.notificationCenter))
                await run.mac.pause(1)
                return LiveCheckTrial(observed: [said(o)], verified: o.ok ? nil : false,
                                      question: "Did Notification Center open on the right of the screen?")
            },
        ]
    }

    // MARK: Windows

    static func windows() -> [LiveCheckStep] {
        let places: [(DeckSystemAction, String)] = [
            (.windowLeft, "the left half of the screen"), (.windowRight, "the right half of the screen"),
            (.windowTop, "the top half of the screen"), (.windowBottom, "the bottom half of the screen"),
            (.windowFill, "fill the screen"), (.windowCenter, "the middle of the screen"),
        ]
        var steps = places.map { action, place in
            LiveCheckStep(id: "window-\(action.rawValue)", group: windowsGroup, title: action.title,
                          summary: "Moves the check's own TextEdit window to \(place) with the \(action.title) button, then puts it back.",
                          needsTestWindows: true) { run in
                guard let placement = WindowPlacement(action) else { return LiveCheckTrial(verified: false) }
                guard await run.mac.focusTestWindow(0) else { return notInFront }
                let screens = run.mac.screens()
                guard let before = run.mac.testWindowFrame(0),
                      let i = WindowTiling.screenIndex(for: before, in: screens) else { return noFrame }
                let expected = WindowTiling.frame(placement, window: before, in: screens[i].visible, gap: run.mac.tileGap())
                let o = await run.mac.perform(.system(action))
                await run.mac.pause(0.6)
                let after = run.mac.testWindowFrame(0)
                return LiveCheckTrial(observed: [said(o), "Window: \(rect(before)), now \(rect(after))", "Expected: \(rect(expected))"],
                                      verified: o.ok && close(after, expected))
            }
        }
        steps.append(LiveCheckStep(id: "window-split", group: windowsGroup, title: DeckSystemAction.windowSplit.title,
                                   summary: "Puts the two TextEdit test windows side by side with the Split Screen button, then puts them back.",
                                   needsTestWindows: true) { run in
            // The second window first, so the first one ends up in front with the second right behind it.
            guard await run.mac.focusTestWindow(1), await run.mac.focusTestWindow(0) else { return notInFront }
            let screens = run.mac.screens()
            guard let first = run.mac.testWindowFrame(0), let i = WindowTiling.screenIndex(for: first, in: screens) else { return noFrame }
            let halves = WindowTiling.split(in: screens[i].visible, gap: run.mac.tileGap())
            let o = await run.mac.perform(.system(.windowSplit))
            await run.mac.pause(0.6)
            let left = run.mac.testWindowFrame(0), right = run.mac.testWindowFrame(1)
            return LiveCheckTrial(observed: [said(o), "Front window: \(rect(left)), expected \(rect(halves.left))",
                                             "Second window: \(rect(right)), expected \(rect(halves.right))"],
                                  verified: o.ok && close(left, halves.left) && close(right, halves.right))
        })
        steps.append(LiveCheckStep(id: "window-next-display", group: windowsGroup, title: DeckSystemAction.windowNextDisplay.title,
                                   summary: "Moves the TextEdit test window to your other display with the Next Display button, then puts it back.",
                                   needsTestWindows: true,
                                   unavailable: { $0.screens().count < 2 ? "Only one display is connected" : nil }) { run in
            guard await run.mac.focusTestWindow(0) else { return notInFront }
            let screens = run.mac.screens()
            guard let before = run.mac.testWindowFrame(0), let i = WindowTiling.screenIndex(for: before, in: screens) else { return noFrame }
            let o = await run.mac.perform(.system(.windowNextDisplay))
            await run.mac.pause(0.6)
            let after = run.mac.testWindowFrame(0)
            let j = after.flatMap { WindowTiling.screenIndex(for: $0, in: screens) }
            return LiveCheckTrial(observed: [said(o), "Window: display \(i + 1), now \(j.map { "display \($0 + 1)" } ?? "unknown")"],
                                  verified: o.ok && j != nil && j != i)
        })
        return steps
    }

    // MARK: Displays

    static func displays() -> [LiveCheckStep] {
        func twoDisplays(_ mac: LiveCheckMac) -> String? {
            (mac.displaysState()?.shownDisplays.count ?? 0) < 2 ? "Only one display is connected" : nil
        }
        return [
            LiveCheckStep(id: "displays-windows", group: displaysGroup, title: "Window List",
                          summary: "Reads the windows the Displays screen would show and looks for the TextEdit test window.",
                          needsTestWindows: true) { run in
                guard await run.mac.focusTestWindow(0) else { return notInFront }
                // Window names are read at most once a second.
                await run.mac.pause(1.2)
                guard let s = run.mac.displaysState(), let id = run.mac.testWindowID(0) else { return noFrame }
                let found = s.window(id)
                return LiveCheckTrial(observed: ["\(s.windows.count) windows on \(s.displays.count) display\(s.displays.count == 1 ? "" : "s")",
                                                 "Test window: \(found.map { "listed as \u{201C}\($0.label)\u{201D}" } ?? "not listed")"],
                                      verified: found?.bundleID == testEditor)
            },
            LiveCheckStep(id: "displays-move", group: displaysGroup, title: "Move a Window",
                          summary: "Moves the TextEdit test window from the Displays screen: to the right half, then a little way in from the top left, then to your other display if there is one. Then puts it back.",
                          needsTestWindows: true) { run in
                guard await run.mac.focusTestWindow(0) else { return notInFront }
                await run.mac.pause(1.2)
                guard let id = run.mac.testWindowID(0), let s = run.mac.displaysState(), let w = s.window(id),
                      let d = s.display(of: w) else { return noFrame }
                var commands: [(String, WindowCommand)] = [
                    ("Right half", .tile(.rightHalf)),
                    ("Dragged", .move(display: d.id, origin: CGPoint(x: d.visibleFrame.minX + 60, y: d.visibleFrame.minY + 60))),
                ]
                if let other = s.shownDisplays.first(where: { $0.id != d.id }) {
                    commands.append(("To \(other.name)", .move(display: other.id, origin: nil)))
                }
                var observed: [String] = []
                var ok = true
                for (name, command) in commands {
                    run.say(name)
                    guard let now = run.mac.displaysState(), let expected = now.frames(for: command, window: id)?.first?.frame else {
                        observed.append("\(name): the window or display went away")
                        ok = false
                        continue
                    }
                    let r = result(run.mac.phone(.windowCommand(id: UUID(), windowID: id, command: command)))
                    await run.mac.pause(0.6)
                    let after = run.mac.testWindowFrame(0)
                    let landed = r.ok && close(after, expected)
                    ok = ok && landed
                    observed.append("\(name): \(r.ok ? rect(after) : r.message ?? "failed")\(landed ? "" : ", expected \(rect(expected))")")
                }
                return LiveCheckTrial(observed: observed, verified: ok)
            },
            LiveCheckStep(id: "displays-resolution", group: displaysGroup, title: "Looks Like and Going Back",
                          summary: "Changes your main display to another Looks like size from the Displays screen and leaves it. After 15 seconds without Keep it should go back by itself.",
                          unavailable: { mac in
                              guard let d = mac.displaysState()?.displays.first(where: \.isMain), d.resolutionID != nil,
                                    d.resolutions.count > 1 else { return "The main display has only one size" }
                              return nil
                          }) { run in
                guard let s = run.mac.displaysState(), let d = s.displays.first(where: \.isMain), let current = d.resolutionID,
                      let i = d.resolutions.firstIndex(where: { $0.id == current }) else { return noFrame }
                let target = d.resolutions[i + 1 < d.resolutions.count ? i + 1 : i - 1]
                run.say("Changing \(d.name) to look like \(target.title)")
                let r = result(run.mac.phone(.displayCommand(id: UUID(), command: .resolution(display: d.id, id: target.id))))
                await run.mac.pause(2.5)
                let changed = run.mac.displaysState()?.display(d.id)?.resolutionID == target.id
                let waiting = run.mac.displaysState()?.pending
                var left = Double(DisplaysMode.keepSeconds) - 2.5 + 3
                while left > 0 {
                    run.say("Waiting for it to go back by itself: \(Int(left.rounded(.up))) s")
                    await run.mac.pause(min(1, left))
                    left -= 1
                }
                let back = run.mac.displaysState()?.display(d.id)?.resolutionID == current
                let cleared = run.mac.displaysState()?.pending == nil
                return LiveCheckTrial(observed: [r.ok ? "Mac accepted \(target.title)" : "Mac refused: \(r.message ?? "no reason given")",
                                                 "Size after 2.5 s: \(changed ? target.title : "unchanged")",
                                                 "Waiting for Keep: \(waiting.map { "\u{201C}\($0.summary)\u{201D}" } ?? "no")",
                                                 "After 18 s: \(back ? "back to \(d.resolution?.title ?? "the old size")" : "not back")"],
                                      verified: r.ok && changed && waiting != nil && back && cleared,
                                      question: "Did the screen change to look like \(target.title), then go back by itself?")
            },
            LiveCheckStep(id: "displays-mirror", group: displaysGroup, title: "Mirroring and Revert",
                          summary: "Makes your other display show the same picture as the main one, then presses Revert.",
                          unavailable: twoDisplays) { run in
                guard let s = run.mac.displaysState(), let main = s.shownDisplays.first(where: \.isMain),
                      let other = s.shownDisplays.first(where: { !$0.isMain }) else { return noFrame }
                let r = result(run.mac.phone(.displayCommand(id: UUID(), command: .mirror(display: other.id, of: main.id))))
                await run.mac.pause(3)
                let mirrored = run.mac.displaysState()?.display(other.id)?.mirrorOf == main.id
                run.say("Pressing Revert")
                let revert = result(run.mac.phone(.displayCommand(id: UUID(), command: .revertChanges)))
                await run.mac.pause(3)
                let own = run.mac.displaysState()?.display(other.id)?.mirrorOf == nil
                return LiveCheckTrial(observed: [r.ok ? "Mac accepted the mirroring" : "Mac refused: \(r.message ?? "no reason given")",
                                                 "Mirrored: \(mirrored ? "yes" : "no")",
                                                 "After Revert: \(own ? "its own picture" : "still mirrored")"],
                                      verified: r.ok && revert.ok && mirrored && own,
                                      question: "Did \(other.name) show the same picture as \(main.name), then its own picture again?")
            },
            LiveCheckStep(id: "displays-main", group: displaysGroup, title: "Main Display",
                          summary: "Makes your other display the main one (the menu bar moves there), then puts it back.",
                          unavailable: twoDisplays) { run in
                guard let s = run.mac.displaysState(), let other = s.shownDisplays.first(where: { !$0.isMain }) else { return noFrame }
                let r = result(run.mac.phone(.displayCommand(id: UUID(), command: .makeMain(display: other.id))))
                await run.mac.pause(3)
                let main = run.mac.displaysState()?.display(other.id)?.isMain == true
                return LiveCheckTrial(observed: [r.ok ? "Mac accepted" : "Mac refused: \(r.message ?? "no reason given")",
                                                 "\(other.name) is the main display: \(main ? "yes" : "no")"],
                                      verified: r.ok && main, question: "Did the menu bar move to \(other.name)?")
            },
            LiveCheckStep(id: "displays-arrange", group: displaysGroup, title: "Arrange",
                          summary: "Moves your other display to the opposite side of the main one, as dragging it on the Displays screen does, then puts it back.",
                          unavailable: twoDisplays) { run in
                guard let s = run.mac.displaysState(), let main = s.shownDisplays.first(where: \.isMain),
                      let other = s.shownDisplays.first(where: { !$0.isMain }) else { return noFrame }
                let to = oppositeSide(of: other.frame, around: main.frame)
                let r = result(run.mac.phone(.displayCommand(id: UUID(), command: .arrange([
                    DisplayOrigin(display: main.id, origin: .zero), DisplayOrigin(display: other.id, origin: to),
                ]))))
                await run.mac.pause(3)
                let now = run.mac.displaysState()?.display(other.id)?.frame.origin
                return LiveCheckTrial(observed: [r.ok ? "Mac accepted" : "Mac refused: \(r.message ?? "no reason given")",
                                                 "\(other.name): \(point(other.frame.origin)), now \(now.map(point) ?? "unknown"), expected \(point(to))"],
                                      verified: r.ok && now == to)
            },
        ]
    }

    /// Where `other` goes on the far side of `main`: left and right swap, else above and below.
    static func oppositeSide(of other: CGRect, around main: CGRect) -> CGPoint {
        if other.minX >= main.maxX { return CGPoint(x: main.minX - other.width, y: other.minY) }
        if other.maxX <= main.minX { return CGPoint(x: main.maxX, y: other.minY) }
        if other.maxY <= main.minY { return CGPoint(x: other.minX, y: main.maxY) }
        return CGPoint(x: other.minX, y: main.minY - other.height)
    }

    // MARK: Screenshots and recording

    static func capture() -> [LiveCheckStep] {
        [
            LiveCheckStep(id: "screenshots", group: captureGroup, title: "Screenshots",
                          summary: "Takes a screenshot of the whole screen and one of the TextEdit test window, as the Screenshot buttons do, checks the files, then moves them to the Trash.",
                          needsTestWindows: true) { run in
                let start = Date()
                let full = await run.mac.perform(.screenshot(DeckScreenshot(area: .fullScreen)))
                guard await run.mac.focusTestWindow(0) else { return notInFront }
                let window = await run.mac.perform(.screenshot(DeckScreenshot(area: .frontWindow, sendToPhone: .photos)))
                await run.mac.pause(0.5)
                let files = run.mac.captures(since: start)
                let sizes = files.compactMap(run.mac.fileSize)
                return LiveCheckTrial(observed: ["Whole screen: \(said(full))", "Test window: \(said(window))",
                                                 "Ready to send to the phone: \(window.image == nil ? "no" : "yes")",
                                                 "Files: \(files.map(\.lastPathComponent).joined(separator: ", "))"],
                                      verified: full.ok && window.ok && window.image != nil && files.count >= 2
                                          && sizes.count == files.count && sizes.allSatisfy { $0 > 0 },
                                      made: files)
            },
            LiveCheckStep(id: "screen-recording", group: captureGroup, title: "Screen Recording",
                          summary: "Records the screen for 3 seconds with the Screen Recording button, checks the file, then moves it to the Trash.") { run in
                let start = Date()
                let first = await run.mac.perform(.screenRecording)
                for left in [3, 2, 1] {
                    run.say("Recording: \(left) s")
                    await run.mac.pause(1)
                }
                let second = await run.mac.perform(.screenRecording)
                run.say("Saving the recording")
                await run.mac.pause(2.5)
                let files = run.mac.captures(since: start).filter { $0.pathExtension == "mov" }
                let size = files.first.flatMap(run.mac.fileSize) ?? 0
                return LiveCheckTrial(observed: ["Start: \(said(first))", "Stop: \(said(second))",
                                                 "File: \(files.first.map { "\($0.lastPathComponent), \(size) bytes" } ?? "none")"],
                                      verified: first.ok && second.ok && size > 0, made: files)
            },
        ]
    }

    // MARK: Sound

    static func sound() -> [LiveCheckStep] {
        [
            LiveCheckStep(id: "volume", group: soundGroup, title: "Volume",
                          summary: "Moves the volume one step with the Volume button, then to another level with the Media slider, then puts it back.",
                          unavailable: { $0.outputVolume() == nil ? "This sound output has no volume control" : nil }) { run in
                guard let before = run.mac.outputVolume() else { return LiveCheckTrial(verified: false) }
                let up = before < 0.9
                let o = await run.mac.perform(.system(up ? .volumeUp : .volumeDown))
                await run.mac.pause(0.3)
                let stepped = run.mac.outputVolume()
                let expected = min(1, max(0, before + (up ? DeckMode.step : -DeckMode.step)))
                let slider = up ? max(0, before - 0.125) : min(1, before + 0.125)
                run.mac.phone(.mediaSetVolume(slider))
                await run.mac.pause(0.3)
                let slid = run.mac.outputVolume()
                return LiveCheckTrial(observed: [said(o), "Volume: \(pct(before)), after the button \(pct(stepped)), expected \(pct(expected))",
                                                 "After the slider: \(pct(slid)), expected \(pct(slider))"],
                                      verified: o.ok && near(stepped, expected) && near(slid, slider))
            },
            LiveCheckStep(id: "mute", group: soundGroup, title: DeckSystemAction.mute.title,
                          summary: "Mutes the sound with the Mute button (or unmutes it if it was muted), then puts it back.",
                          unavailable: { $0.outputMuted() == nil ? "This sound output cannot be muted" : nil }) { run in
                let before = run.mac.outputMuted()
                let o = await run.mac.perform(.system(.mute))
                let after = run.mac.outputMuted()
                return LiveCheckTrial(observed: [said(o), "Muted: \(yesNo(before)), now \(yesNo(after))"],
                                      verified: check(o, changed(before, after)))
            },
            LiveCheckStep(id: "mic-mute", group: soundGroup, title: DeckSystemAction.micMute.title,
                          summary: "Mutes the microphone with the Mute Microphone button (or turns it on if it was muted), then puts it back.",
                          unavailable: { $0.inputMuted() == nil ? "No microphone found" : nil }) { run in
                let before = run.mac.inputMuted()
                let o = await run.mac.perform(.system(.micMute))
                let after = run.mac.inputMuted()
                return LiveCheckTrial(observed: [said(o), "Microphone muted: \(yesNo(before)), now \(yesNo(after))"],
                                      verified: check(o, changed(before, after)))
            },
        ]
    }

    // MARK: Brightness and Night Shift

    static func brightness() -> [LiveCheckStep] {
        [
            LiveCheckStep(id: "brightness", group: brightnessGroup, title: "Brightness",
                          summary: "Moves the brightness one step with the Brightness button, then to another level with the Displays slider, then puts it back.",
                          unavailable: { $0.brightness() == nil ? "This display's brightness cannot be changed from Glasspad" : nil }) { run in
                guard let before = run.mac.brightness() else { return LiveCheckTrial(verified: false) }
                let down = before > 0.5
                let o = await run.mac.perform(.system(down ? .brightnessDown : .brightnessUp))
                await run.mac.pause(0.4)
                let stepped = run.mac.brightness()
                let expected = min(1, max(0, before + (down ? -DeckMode.step : DeckMode.step)))
                var observed = [said(o), "Brightness: \(pct(before)), after the button \(pct(stepped)), expected \(pct(expected))"]
                var ok = o.ok && near(stepped, expected)
                if let main = run.mac.displaysState()?.displays.first(where: \.isMain), main.brightness != nil {
                    let slider = down ? min(1, before + 0.1) : max(0, before - 0.1)
                    let r = result(run.mac.phone(.displayCommand(id: UUID(), command: .brightness(display: main.id, value: slider))))
                    await run.mac.pause(0.4)
                    let slid = run.mac.brightness()
                    observed.append("After the slider: \(pct(slid)), expected \(pct(slider))")
                    ok = ok && r.ok && near(slid, slider)
                }
                return LiveCheckTrial(observed: observed, verified: ok)
            },
            LiveCheckStep(id: "night-shift", group: brightnessGroup, title: "Night Shift",
                          summary: "Switches Night Shift with the Night Shift button, then switches it back.") { run in
                let before = run.mac.nightShift()
                let o = await run.mac.perform(.system(.nightShift))
                await run.mac.pause(1)
                let after = run.mac.nightShift()
                return LiveCheckTrial(observed: [said(o), "Night Shift: \(onOff(before)), now \(onOff(after))"],
                                      verified: check(o, changed(before, after)),
                                      question: after == false ? "Did the screen go back to its usual colors?" : "Did the screen turn warmer?")
            },
        ]
    }

    // MARK: Media

    static func media() -> [LiveCheckStep] {
        let ready = "Start a song playing in Music or Spotify first."
        return [
            LiveCheckStep(id: "play-pause", group: mediaGroup, title: DeckSystemAction.playPause.title,
                          summary: "Presses Play or Pause twice, 2 seconds apart.", getReady: ready, touchesPlayback: true) { run in
                let s0 = await run.mac.nowPlaying()
                let first = await run.mac.perform(.system(.playPause))
                await run.mac.pause(2)
                let s1 = await run.mac.nowPlaying()
                let second = await run.mac.perform(.system(.playPause))
                await run.mac.pause(2)
                let s2 = await run.mac.nowPlaying()
                let source = s0?.sourceName ?? "The player"
                var verified: Bool?
                if let a = s0?.isPlaying, let b = s1?.isPlaying, let c = s2?.isPlaying { verified = b != a && c == a }
                let order = s0?.isPlaying == false ? "play and then pause" : "pause and then play again"
                return LiveCheckTrial(observed: ["Playing: \(yesNo(s0?.isPlaying)), then \(yesNo(s1?.isPlaying)), then \(yesNo(s2?.isPlaying))"],
                                      verified: first.ok && second.ok ? verified : false,
                                      question: "Did \(source) \(order)?")
            },
            LiveCheckStep(id: "next-previous", group: mediaGroup, title: "Next and Previous Track",
                          summary: "Presses Next Track, then Previous Track, 2 seconds apart.", getReady: ready, touchesPlayback: true) { run in
                let s0 = await run.mac.nowPlaying()
                let next = await run.mac.perform(.system(.nextTrack))
                await run.mac.pause(2)
                let s1 = await run.mac.nowPlaying()
                let previous = await run.mac.perform(.system(.previousTrack))
                await run.mac.pause(2)
                let s2 = await run.mac.nowPlaying()
                return LiveCheckTrial(observed: ["Song: \(title(s0)), then \(title(s1)), then \(title(s2))"],
                                      verified: next.ok && previous.ok ? nil : false,
                                      question: "Did it skip to the next song, then go back?")
            },
        ]
    }

    // MARK: Remote

    /// Players the Remote has its own keys for, with the name to use when one is not installed.
    static let players: [(bundleID: String, name: String)] = [
        ("com.apple.Music", "Music"), ("com.spotify.client", "Spotify"), ("com.apple.TV", "TV"),
        ("com.apple.QuickTimePlayerX", "QuickTime Player"), ("com.colliderli.iina", "IINA"), ("org.videolan.vlc", "VLC"),
        ("com.firecore.infuse", "Infuse"),
    ]

    static func remote() -> [LiveCheckStep] {
        players.map { player in
            LiveCheckStep(id: "remote-\(player.bundleID)", group: remoteGroup, title: player.name,
                          summary: "Sends the Remote's keys to \(player.name), 2 seconds apart, the way the phone does: play and pause, back and forward, full screen, and subtitles where it has them.",
                          getReady: "Open something to watch or listen to in \(player.name) and start it playing.",
                          touchesPlayback: true,
                          unavailable: { $0.appName(player.bundleID) == nil ? "\(player.name) is not installed" : nil }) { run in
                let name = run.mac.appName(player.bundleID) ?? player.name
                guard run.mac.isRunning(player.bundleID) else { return LiveCheckTrial(observed: ["\(name) was not open"], verified: false) }
                guard await run.mac.activate(player.bundleID) else {
                    return LiveCheckTrial(observed: ["\(name) would not come to the front"], verified: false)
                }
                run.mac.phone(.modeSelected(.remote))
                await run.mac.pause(1.5)
                let playing = await run.mac.nowPlaying()
                let front = run.mac.frontmostBundleID()
                let keymap = RemoteKeymap(frontmost: front, playing: playing?.sourceBundleID,
                                          nowPlaying: [playing?.title, playing?.artist, playing?.album])
                let presses = remotePresses(keymap, canSeek: playing?.canSeek ?? false)
                var observed = ["In front: \(front ?? "nothing")", "Playing: \(playing?.sourceName ?? "nothing")",
                                "Remote keys for: \(keymap.name ?? name)"]
                var sent: [String] = []
                for press in presses {
                    run.say("Sending: \(press.words)")
                    guard let output = keymap.output(press.action) else { continue }
                    let state = await run.mac.nowPlaying()
                    let messages = RemoteKeymap.message(for: output, position: state?.elapsed, canSeek: state?.canSeek ?? false,
                                                        duration: state?.duration)
                    for m in messages { run.mac.phone(m) }
                    if !messages.isEmpty { sent.append(press.words) }
                    await run.mac.pause(2)
                }
                run.mac.phone(.modeSelected(.trackpad))
                observed.append("Sent: \(sent.joined(separator: ", "))")
                return LiveCheckTrial(observed: observed, verified: sent.isEmpty ? false : nil,
                                      question: "Did \(name) \(list(sent))? If one did not, say which in the note.")
            }
        }
    }

    struct RemotePress: Equatable {
        var action: RemoteAction
        var words: String
    }

    /// The presses for this player, each one undone by the next where it can be.
    static func remotePresses(_ keymap: RemoteKeymap, canSeek: Bool) -> [RemotePress] {
        let skips = keymap.skipsTracks
        let all = [
            RemotePress(action: .playPause, words: "pause"), RemotePress(action: .playPause, words: "play"),
            RemotePress(action: .forward, words: skips ? "skip to the next song" : "jump forward"),
            RemotePress(action: .back, words: skips ? "go back a song" : "jump back"),
            RemotePress(action: .fullScreen, words: "go full screen"), RemotePress(action: .fullScreen, words: "leave full screen"),
            RemotePress(action: .subtitles, words: "turn subtitles on"), RemotePress(action: .subtitles, words: "turn subtitles off"),
        ]
        return all.filter { keymap.has($0.action, canSeek: canSeek) }
    }

    // MARK: Dock

    static func dock() -> [LiveCheckStep] {
        [
            LiveCheckStep(id: "dock-hide", group: dockGroup, title: "Hide Mac Dock",
                          summary: "Hides the Mac's Dock with the phone's Hide Mac Dock switch, then brings it back.") { run in
                let before = run.mac.dock()
                run.mac.phone(.macDockSet(MacDockState(hidden: true, hideWhileConnected: before.hideWhileConnected)))
                await run.mac.pause(2)
                let after = run.mac.dock()
                let delay = run.mac.dockRevealDelay()
                return LiveCheckTrial(observed: ["Hidden: \(before.isHiddenNow ? "yes" : "no"), now \(after.isHiddenNow ? "yes" : "no")",
                                                 "Dock reveal delay: \(delay.map { "\(Int($0)) s" } ?? "not set")"],
                                      verified: after.isHiddenNow && delay == MacDockHider.hiddenDelay,
                                      question: "Is the Dock gone, even when you move the pointer to the bottom of the screen?")
            },
        ]
    }

    // MARK: Shortcuts

    static func shortcuts() -> [LiveCheckStep] {
        [
            LiveCheckStep(id: "shortcut-missing", group: shortcutsGroup, title: "Missing Shortcut",
                          summary: "Runs a shortcut that does not exist and checks the message the phone would show.") { run in
                let name = "Glasspad Live Check \(UUID().uuidString.prefix(4))"
                let o = await run.mac.perform(.runShortcut(name: name))
                let none = await run.mac.shortcutNames().isEmpty
                // With no shortcuts at all the Mac cannot tell a missing one from a failed one.
                let expected = none ? "Shortcut \u{201C}\(name)\u{201D} stopped with an error"
                    : "There is no shortcut named \u{201C}\(name)\u{201D} on this Mac"
                return LiveCheckTrial(observed: [said(o), "Expected: \(expected)"], verified: !o.ok && o.message == expected)
            },
        ]
    }

    // MARK: Lock, sleep and disks

    static func disruptive() -> [LiveCheckStep] {
        [
            LiveCheckStep(id: "lock-screen", group: disruptiveGroup, title: DeckSystemAction.lockScreen.title,
                          summary: "Locks the screen right away. Unlock it, then answer.", disruptive: true) { run in
                let o = await run.mac.perform(.system(.lockScreen))
                return LiveCheckTrial(observed: [said(o)], verified: o.ok ? nil : false, question: "Did the screen lock?")
            },
            LiveCheckStep(id: "sleep-display", group: disruptiveGroup, title: DeckSystemAction.sleepDisplay.title,
                          summary: "Turns the display off. Press a key to wake it, then answer.", disruptive: true) { run in
                let o = await run.mac.perform(.system(.sleepDisplay))
                return LiveCheckTrial(observed: [said(o)], verified: o.ok ? nil : false, question: "Did the display turn off?")
            },
            LiveCheckStep(id: "sleep-mac", group: disruptiveGroup, title: DeckSystemAction.sleepMac.title,
                          summary: "Puts the Mac to sleep. Wake it, then answer.", disruptive: true) { run in
                let o = await run.mac.perform(.system(.sleepMac))
                return LiveCheckTrial(observed: [said(o)], verified: o.ok ? nil : false, question: "Did the Mac go to sleep?")
            },
            LiveCheckStep(id: "empty-trash", group: disruptiveGroup, title: DeckSystemAction.emptyTrash.title,
                          summary: "Empties the Trash. Everything in it is deleted for good, so press Skip if you want to keep it.",
                          disruptive: true) { run in
                let o = await run.mac.perform(.system(.emptyTrash))
                return LiveCheckTrial(observed: [said(o)], verified: o.ok ? nil : false, question: "Is the Trash empty now?")
            },
            LiveCheckStep(id: "eject-all", group: disruptiveGroup, title: DeckSystemAction.ejectAll.title,
                          summary: "Ejects every disk that can be ejected, such as USB drives and disk images. Press Skip if one is in use.",
                          disruptive: true) { run in
                let o = await run.mac.perform(.system(.ejectAll))
                return LiveCheckTrial(observed: [said(o)], verified: o.ok)
            },
        ]
    }

    // MARK: Helpers

    static let testEditor = "com.apple.TextEdit"

    static let notInFront = LiveCheckTrial(observed: ["The test window would not come to the front, so nothing was moved"], verified: false)
    static let noFrame = LiveCheckTrial(observed: ["Could not read where things are on the screen"], verified: false)

    /// What Glasspad would tell the phone.
    static func said(_ o: DeckMode.Outcome) -> String {
        o.ok ? "Glasspad said: \(o.message ?? "Done")" : "Glasspad said it failed: \(o.message ?? "no reason given")"
    }

    /// The Displays result among the Mac's answers.
    static func result(_ replies: [ModeMessage]) -> (ok: Bool, message: String?) {
        for r in replies { if case .displaysResult(_, let ok, let message) = r { return (ok, message) } }
        return (false, "No answer from the Mac")
    }

    /// False when the button failed; otherwise what the readings say (nil when they cannot tell).
    static func check(_ o: DeckMode.Outcome, _ reading: Bool?) -> Bool? { o.ok ? reading : false }

    static func changed(_ a: Bool?, _ b: Bool?) -> Bool? {
        guard let a, let b else { return nil }
        return a != b
    }

    static func close(_ a: CGRect?, _ b: CGRect) -> Bool { a.map { WindowTiling.isClose($0, b, tolerance: 4) } ?? false }
    static func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) <= 0.02 } ?? false }

    static func look(_ dark: Bool?) -> String { dark.map { $0 ? "Dark" : "Light" } ?? "unknown" }
    static func onOff(_ v: Bool?) -> String { v.map { $0 ? "on" : "off" } ?? "unknown" }
    static func yesNo(_ v: Bool?) -> String { v.map { $0 ? "yes" : "no" } ?? "unknown" }
    static func pct(_ v: Double?) -> String { v.map { LiveCheckRestorer.percent($0) } ?? "unknown" }
    static func title(_ s: MediaState?) -> String { s?.title.map { "\u{201C}\($0)\u{201D}" } ?? "unknown" }

    static func rect(_ r: CGRect?) -> String {
        guard let r else { return "unknown" }
        return "\(Int(r.minX.rounded())), \(Int(r.minY.rounded())), \(Int(r.width.rounded())) × \(Int(r.height.rounded()))"
    }

    static func point(_ p: CGPoint) -> String { "\(Int(p.x.rounded())), \(Int(p.y.rounded()))" }

    /// "pause, play and jump forward".
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}
