import Foundation
import CoreGraphics
import Testing
@testable import GlasspadMacros

// ANSI key codes used below.
private let kT: UInt16 = 0x11, kH: UInt16 = 0x04, kI: UInt16 = 0x22, kDelete: UInt16 = 0x33
private let kReturn: UInt16 = 0x24, kPeriod: UInt16 = 0x2F, kSpace: UInt16 = 0x31

private func key(_ t: Double, _ code: UInt16, _ chars: String, _ mods: KeyModifiers = [], repeat r: Bool = false) -> RecordedEvent {
    RecordedEvent(time: t, kind: .keyDown(keyCode: code, characters: chars, modifiers: mods, isRepeat: r))
}
private func move(_ t: Double, _ x: Double, _ y: Double) -> RecordedEvent {
    RecordedEvent(time: t, kind: .mouseMoved(CGPoint(x: x, y: y)))
}
private func down(_ t: Double, _ x: Double, _ y: Double, count: Int = 1, _ b: MouseButton = .left,
                  mods: KeyModifiers = [], frame: CGRect? = nil) -> RecordedEvent {
    RecordedEvent(time: t, kind: .mouseDown(b, CGPoint(x: x, y: y), clickCount: count, modifiers: mods), windowFrame: frame)
}
private func up(_ t: Double, _ x: Double, _ y: Double, _ b: MouseButton = .left) -> RecordedEvent {
    RecordedEvent(time: t, kind: .mouseUp(b, CGPoint(x: x, y: y)))
}
private func dragged(_ t: Double, _ x: Double, _ y: Double) -> RecordedEvent {
    RecordedEvent(time: t, kind: .mouseDragged(.left, CGPoint(x: x, y: y)))
}
private func scroll(_ t: Double, _ dy: Int) -> RecordedEvent {
    RecordedEvent(time: t, kind: .scroll(dx: 0, dy: dy))
}

@Suite("Recorder coalescing")
struct CoalescerTests {
    let noTiming = RecordingCoalescer(options: RecordingOptions(keepTiming: false))

    @Test func typedCharactersCollapseIntoOneTypeTextStep() {
        let steps = noTiming.steps(from: [
            key(0.00, kH, "H", [.shift]), key(0.05, kI, "i"), key(0.10, kSpace, " "),
            key(0.15, kT, "t"), key(0.20, kI, "é", [.option]),
        ])
        #expect(steps == [.typeText("Hi té")])
    }

    @Test func deleteEditsTheTextRunInsteadOfRecordingAKey() {
        let steps = noTiming.steps(from: [
            key(0, kH, "h"), key(0.1, kI, "x"), key(0.2, kDelete, "\u{7F}"), key(0.3, kI, "i"),
            key(0.4, kDelete, "\u{7F}"), key(0.5, kDelete, "\u{7F}"), key(0.6, kDelete, "\u{7F}"),
        ])
        // "hx" -> "h" -> "hi" -> "h" -> "" ; the last Delete has no text left, so it is a real key press.
        #expect(steps == [.keystroke(KeyCombo(.special(.delete)))])
    }

    @Test func shortcutsAndNonPrintingKeysBecomeKeystrokes() {
        let steps = noTiming.steps(from: [
            key(0, kT, "t", [.command, .shift]), key(0.1, kH, "h"), key(0.2, kI, "i"),
            key(0.3, kReturn, "\r"), key(0.4, 0x7E, "\u{F700}"), key(0.5, kT, "\u{14}", [.control]),
        ])
        #expect(steps == [
            .keystroke(KeyCombo("t", [.shift, .command])),
            .typeText("hi"),
            .keystroke(KeyCombo(.special(.returnKey))),
            .keystroke(KeyCombo(.special(.up))),
            .keystroke(KeyCombo("t", [.control])),
        ])
    }

    @Test func movesCollapseAndVanishBeforeAClick() {
        var events: [RecordedEvent] = []
        for i in 0..<50 { events.append(move(Double(i) * 0.008, Double(i * 4), Double(i * 2))) }
        events += [down(0.5, 300, 150), up(0.55, 301, 150)]
        // A hover move at the end is kept, collapsed to where the pointer stopped.
        for i in 0..<20 { events.append(move(0.6 + Double(i) * 0.008, 400 + Double(i), 200)) }
        let steps = noTiming.steps(from: events)
        #expect(steps == [
            .click(button: .left, at: .screen(300, 150), count: 1, modifiers: []),
            .moveMouse(to: .screen(419, 200)),
        ])
    }

    @Test func doubleAndTripleClicksMerge() {
        let steps = noTiming.steps(from: [
            down(0, 50, 50, count: 1), up(0.05, 50, 50),
            down(0.15, 50, 51, count: 2), up(0.2, 50, 51),
            down(0.3, 51, 51, count: 3), up(0.35, 51, 51),
            down(1.5, 50, 50, count: 1, .right, mods: [.control]), up(1.55, 50, 50, .right),
        ])
        #expect(steps == [
            .click(button: .left, at: .screen(50, 50), count: 3, modifiers: []),
            .click(button: .right, at: .screen(50, 50), count: 1, modifiers: [.control]),
        ])
    }

    @Test func pressMoveReleaseIsADrag() {
        let steps = noTiming.steps(from: [
            down(0, 100, 100), dragged(0.1, 150, 120), dragged(0.2, 200, 140), up(0.4, 200, 140),
            // Wobble within the slop is still a click.
            down(1.0, 10, 10), dragged(1.05, 12, 11), up(1.1, 10, 10),
        ])
        #expect(steps == [
            .drag(button: .left, from: .screen(100, 100), to: .screen(200, 140), durationMs: 400),
            .click(button: .left, at: .screen(10, 10), count: 1, modifiers: []),
        ])
    }

    @Test func scrollBurstsMergeAndThePointerPositionIsKept() {
        let steps = noTiming.steps(from: [
            move(0, 640, 400),
            scroll(0.10, -10), scroll(0.12, -20), scroll(0.15, -30),
            scroll(1.00, 5), // after a pause: a new scroll
        ])
        #expect(steps == [.moveMouse(to: .screen(640, 400)), .scroll(dx: 0, dy: -60), .scroll(dx: 0, dy: 5)])
    }

    @Test func pausesBecomeWaitsRoundedCappedAndFiltered() {
        let c = RecordingCoalescer(options: RecordingOptions(minWaitMs: 50, maxWaitMs: 2000))
        let steps = c.steps(from: [
            key(10.000, kT, "t", [.command]),
            key(10.030, kT, "t", [.command]),     // 30 ms gap: dropped
            key(10.534, kH, "h"),                 // 504 ms gap -> 500
            key(10.600, kI, "i"),                 // inside the text run: absorbed
            key(19.000, kReturn, "\r"),           // 8.4 s gap -> capped at 2000
        ])
        #expect(steps == [
            .keystroke(KeyCombo("t", [.command])),
            .keystroke(KeyCombo("t", [.command])),
            .wait(ms: 500),
            .typeText("hi"),
            .wait(ms: 2000),
            .keystroke(KeyCombo(.special(.returnKey))),
        ])
    }

    @Test func windowRelativeRecordingUsesTheFrameAtPressTime() {
        let c = RecordingCoalescer(options: RecordingOptions(positions: .frontWindow, keepTiming: false))
        let frame = CGRect(x: 200, y: 100, width: 800, height: 600)
        let steps = c.steps(from: [
            down(0, 250, 130, frame: frame), up(0.05, 250, 130),
            down(1, 300, 300, frame: frame), dragged(1.1, 500, 400), up(1.2, 500, 400),
            down(2, 5, 5, frame: nil), up(2.05, 5, 5), // no window: falls back to screen
        ])
        #expect(steps == [
            .click(button: .left, at: .window(50, 30), count: 1, modifiers: []),
            .drag(button: .left, from: .window(100, 200), to: .window(300, 300), durationMs: 200),
            .click(button: .left, at: .screen(5, 5), count: 1, modifiers: []),
        ])
    }

    @Test func unfinishedPressIsDropped() {
        #expect(noTiming.steps(from: [key(0, kH, "h"), down(0.1, 1, 1)]) == [.typeText("h")])
    }

    @Test func convertsRealQuartzEventsWithoutPostingThem() throws {
        // Events are only constructed, never posted.
        let k = try #require(CGEvent(keyboardEventSource: nil, virtualKey: kT, keyDown: true))
        k.flags = [.maskCommand, .maskShift]
        var chars: [UniChar] = Array("T".utf16)
        k.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        let rk = try #require(RecordedEvent(cgEvent: k, type: .keyDown))
        #expect(rk.kind == .keyDown(keyCode: kT, characters: "T", modifiers: [.shift, .command], isRepeat: false))

        let m = try #require(CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown,
                                     mouseCursorPosition: CGPoint(x: 12, y: 34), mouseButton: .right))
        m.flags = []   // a nil-source event copies the keys held on this Mac right now
        m.setIntegerValueField(.mouseEventClickState, value: 2)
        let rm = try #require(RecordedEvent(cgEvent: m, type: .rightMouseDown))
        #expect(rm.kind == .mouseDown(.right, CGPoint(x: 12, y: 34), clickCount: 2, modifiers: []))

        let s = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                     wheel1: -7, wheel2: 3, wheel3: 0))
        s.flags = []
        let rs = try #require(RecordedEvent(cgEvent: s, type: .scrollWheel))
        #expect(rs.kind == .scroll(dx: 3, dy: -7))

        // Playback's own events are recognisable by their marker.
        k.setIntegerValueField(.eventSourceUserData, value: MacroEventMarker.userData)
        #expect(k.isFromMacroPlayback)
    }
}

@Suite("Recorder session and secure input")
struct RecorderSessionTests {
    @Test func refusesToStartWhileSecureInputIsOn() {
        let source = FakeRecordingSource()
        let secure = FakeSecureInput()
        secure.set(true)
        let recorder = MacroRecorder(source: source, secureInput: secure, windows: FakeWindows())
        #expect(throws: MacroError.secureInputActive) { try recorder.start() }
        #expect(!recorder.isRecording)
        #expect(!source.isRunning)
    }

    @Test func dropsKeysTypedWhileSecureInputComesOnMidRecording() throws {
        let source = FakeRecordingSource()
        let secure = FakeSecureInput()
        let recorder = MacroRecorder(source: source, secureInput: secure, windows: FakeWindows())
        try recorder.start(options: RecordingOptions(keepTiming: false))
        source.emit(key(0, kH, "u"))
        secure.set(true) // a password field gets focus
        for (i, c) in "hunter2".enumerated() { source.emit(key(0.1 + Double(i) * 0.05, kH, String(c))) }
        source.emit(down(1, 10, 10)); source.emit(up(1.05, 10, 10)) // clicks still record
        secure.set(false)
        source.emit(key(2, kI, "k"))
        let result = try recorder.stop()
        #expect(result.steps == [.typeText("u"), .click(button: .left, at: .screen(10, 10), count: 1, modifiers: []),
                                 .typeText("k")])
        #expect(result.droppedSecureKeyEvents == 7)
        #expect(!source.isRunning)
    }

    @Test func stopHotkeyEndsRecordingAndIsNotRecorded() throws {
        let source = FakeRecordingSource()
        let recorder = MacroRecorder(source: source, secureInput: FakeSecureInput(), windows: FakeWindows())
        let got = LockedBox<RecordingResult?>(nil)
        try recorder.start(options: RecordingOptions(keepTiming: false)) { got.set($0) }
        source.emit(key(0, kT, "t", [.command]))
        source.emit(key(0.5, kPeriod, ".", [.control, .option, .command]))
        source.emit(key(0.6, kH, "h")) // after stopping: ignored
        let result = try #require(got.get())
        #expect(result.steps == [.keystroke(KeyCombo("t", [.command]))])
        #expect(result.stoppedByHotkey)
        #expect(!recorder.isRecording)
        #expect(throws: MacroError.notRecording) { try recorder.stop() }
    }

    @Test func capturesWindowFrameOnPressWhenRecordingRelative() throws {
        let source = FakeRecordingSource()
        let windows = FakeWindows(frame: CGRect(x: 100, y: 50, width: 400, height: 300))
        let recorder = MacroRecorder(source: source, secureInput: FakeSecureInput(), windows: windows)
        try recorder.start(options: RecordingOptions(positions: .frontWindow, keepTiming: false))
        source.emit(move(0, 1, 1))
        source.emit(down(0.1, 130, 70)); source.emit(up(0.15, 130, 70))
        let result = try recorder.stop()
        #expect(result.steps == [.click(button: .left, at: .window(30, 20), count: 1, modifiers: [])])
        #expect(windows.frameQueries == 1) // only presses query the window, never moves
    }

    @Test func stoppingFromTheMacMenuDropsTheMenuClick() throws {
        let source = FakeRecordingSource()
        let recorder = MacroRecorder(source: source, secureInput: FakeSecureInput(), windows: FakeWindows())
        try recorder.start()
        source.emit(key(0, kT, "t", [.command]))
        source.emit(down(2, 1400, 10)); source.emit(up(2.05, 1400, 10)) // the menu bar item
        #expect(try recorder.stop(discardTrailingClick: true).steps == [.keystroke(KeyCombo("t", [.command]))])
        #expect(MacroRecorder.trimTrailingClick([.typeText("a")]) == [.typeText("a")])
    }

    @Test func startFailsCleanlyWithoutInputMonitoring() {
        let source = FakeRecordingSource()
        source.failWith = .inputMonitoringNotGranted
        let recorder = MacroRecorder(source: source, secureInput: FakeSecureInput(), windows: FakeWindows())
        #expect(throws: MacroError.inputMonitoringNotGranted) { try recorder.start() }
        #expect(!recorder.isRecording)
        #expect(throws: MacroError.alreadyRecording) {
            source.failWith = nil
            try recorder.start()
            try recorder.start()
        }
    }
}
