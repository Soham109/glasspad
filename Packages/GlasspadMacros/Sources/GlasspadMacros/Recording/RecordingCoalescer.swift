import Foundation
import CoreGraphics

/// One raw input event seen while recording.
public struct RecordedEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `characters` is what the key typed with its modifiers applied.
        case keyDown(keyCode: UInt16, characters: String, modifiers: KeyModifiers, isRepeat: Bool)
        case mouseDown(MouseButton, CGPoint, clickCount: Int, modifiers: KeyModifiers)
        case mouseUp(MouseButton, CGPoint)
        case mouseMoved(CGPoint)
        case mouseDragged(MouseButton, CGPoint)
        /// Pixel deltas, Quartz convention (positive dy = up).
        case scroll(dx: Int, dy: Int)
    }

    /// Seconds, any monotonic origin.
    public var time: Double
    public var kind: Kind
    /// Frontmost window frame when the event happened. Filled in for mouse
    /// downs when recording window-relative positions.
    public var windowFrame: CGRect?

    public init(time: Double, kind: Kind, windowFrame: CGRect? = nil) {
        self.time = time
        self.kind = kind
        self.windowFrame = windowFrame
    }
}

public struct RecordingOptions: Sendable {
    public enum Positions: String, Codable, Sendable {
        /// Absolute screen points.
        case screen
        /// Clicks and drags relative to the frontmost window's top-left, so the
        /// macro still works after the window moves.
        case frontWindow
    }

    public var positions: Positions
    /// Keep the user's pauses as wait steps.
    public var keepTiming: Bool
    /// Pauses shorter than this are dropped.
    public var minWaitMs: Int
    /// Long pauses (the user thinking) are capped to this.
    public var maxWaitMs: Int
    /// Pressing this stops the recording; it is never recorded itself.
    public var stopHotkey: KeyCombo
    /// A press and release within this many points is a click, not a drag.
    public var clickSlop: Double
    /// Scroll events closer together than this merge into one step.
    public var scrollMergeGapMs: Int

    public init(positions: Positions = .screen, keepTiming: Bool = true, minWaitMs: Int = 50,
                maxWaitMs: Int = 5000, stopHotkey: KeyCombo = KeyCombo(".", [.control, .option, .command]),
                clickSlop: Double = 4, scrollMergeGapMs: Int = 300) {
        self.positions = positions
        self.keepTiming = keepTiming
        self.minWaitMs = minWaitMs
        self.maxWaitMs = maxWaitMs
        self.stopHotkey = stopHotkey
        self.clickSlop = clickSlop
        self.scrollMergeGapMs = scrollMergeGapMs
    }
}

/// Turns a raw event stream into tidy macro steps:
/// - runs of typed characters become one `typeText` (Delete edits the run);
/// - shortcut keys (with Command or Control, or non-printing keys) become `keystroke`;
/// - pointer moves collapse to their end point, and vanish before a click
///   because the click carries its own position;
/// - press/release becomes a click, or a drag if the pointer travelled;
///   consecutive clicks with rising click counts merge into a double/triple click;
/// - bursts of scroll events merge into one scroll step;
/// - pauses between steps become `wait` steps.
public struct RecordingCoalescer {
    public var options: RecordingOptions
    public var layout: KeyboardLayoutMap

    public init(options: RecordingOptions = .init(), layout: KeyboardLayoutMap = .ansi) {
        self.options = options
        self.layout = layout
    }

    struct Timed {
        var step: MacroStep
        var start: Double
        var end: Double
    }

    private struct PendingDown {
        var button: MouseButton
        var point: CGPoint
        var clickCount: Int
        var modifiers: KeyModifiers
        var frame: CGRect?
        var time: Double
        var maxDistance: Double = 0
    }

    /// Is this key press plain typing rather than a shortcut?
    static func isTyping(characters: String, modifiers: KeyModifiers) -> Bool {
        guard modifiers.intersection([.command, .control]).isEmpty, !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { s in
            !CharacterSet.controlCharacters.contains(s) && !(0xF700...0xF8FF).contains(s.value) && s.value != 0x7F
        }
    }

    public func steps(from events: [RecordedEvent]) -> [MacroStep] {
        let timed = timedSteps(from: events)
        guard options.keepTiming else { return timed.map(\.step) }
        var result: [MacroStep] = []
        for (i, t) in timed.enumerated() {
            if i > 0 {
                let gapMs = (t.start - timed[i - 1].end) * 1000
                if gapMs >= Double(options.minWaitMs) {
                    let rounded = Int((gapMs / 10).rounded()) * 10
                    result.append(.wait(ms: min(rounded, options.maxWaitMs)))
                }
            }
            result.append(t.step)
        }
        return result
    }

    func timedSteps(from events: [RecordedEvent]) -> [Timed] {
        var out: [Timed] = []
        var text: (value: String, start: Double, end: Double)?
        var move: (point: CGPoint, time: Double)?
        var down: PendingDown?
        var scroll: (dx: Int, dy: Int, start: Double, end: Double)?

        func flushText() {
            if let t = text, !t.value.isEmpty { out.append(Timed(step: .typeText(t.value), start: t.start, end: t.end)) }
            text = nil
        }
        func flushMove() {
            if let m = move { out.append(Timed(step: .moveMouse(to: .screen(m.point.x, m.point.y)), start: m.time, end: m.time)) }
            move = nil
        }
        func flushScroll() {
            if let s = scroll, s.dx != 0 || s.dy != 0 {
                out.append(Timed(step: .scroll(dx: s.dx, dy: s.dy), start: s.start, end: s.end))
            }
            scroll = nil
        }
        func point(_ p: CGPoint, frame: CGRect?) -> MacroPoint {
            if options.positions == .frontWindow, let f = frame {
                return .window(p.x - f.minX, p.y - f.minY)
            }
            return .screen(p.x, p.y)
        }

        for event in events {
            switch event.kind {
            case .keyDown(let code, let chars, let mods, _):
                flushMove()
                flushScroll()
                let key = layout.key(for: code)
                if Self.isTyping(characters: chars, modifiers: mods) {
                    if text == nil { text = ("", event.time, event.time) }
                    text!.value += chars
                    text!.end = event.time
                } else if key == .special(.delete), mods.isEmpty, let t = text, !t.value.isEmpty {
                    text!.value.removeLast()
                    text!.end = event.time
                } else {
                    flushText()
                    out.append(Timed(step: .keystroke(KeyCombo(key, mods)), start: event.time, end: event.time))
                }

            case .mouseMoved(let p):
                move = (p, event.time)

            case .mouseDown(let button, let p, let count, let mods):
                flushText()
                flushScroll()
                move = nil // the click carries its own position
                down = PendingDown(button: button, point: p, clickCount: count, modifiers: mods,
                                   frame: event.windowFrame, time: event.time)

            case .mouseDragged(let button, let p):
                guard var d = down, d.button == button else { continue }
                d.maxDistance = max(d.maxDistance, hypot(p.x - d.point.x, p.y - d.point.y))
                down = d

            case .mouseUp(let button, let p):
                guard let d = down, d.button == button else { continue }
                down = nil
                let distance = max(d.maxDistance, hypot(p.x - d.point.x, p.y - d.point.y))
                if distance > options.clickSlop {
                    let ms = Int(((event.time - d.time) * 1000).rounded())
                    out.append(Timed(step: .drag(button: button, from: point(d.point, frame: d.frame),
                                                 to: point(p, frame: d.frame), durationMs: max(ms, 50)),
                                     start: d.time, end: event.time))
                    continue
                }
                let here = point(d.point, frame: d.frame)
                if d.clickCount >= 2, let last = out.last,
                   case .click(let lb, let lp, let ln, let lm) = last.step,
                   lb == button, ln == d.clickCount - 1, lm == d.modifiers,
                   hypot(lp.x - here.x, lp.y - here.y) <= options.clickSlop * 2, lp.reference == here.reference {
                    out[out.count - 1] = Timed(step: .click(button: button, at: lp, count: min(d.clickCount, 3), modifiers: lm),
                                               start: last.start, end: event.time)
                } else {
                    out.append(Timed(step: .click(button: button, at: here, count: 1, modifiers: d.modifiers),
                                     start: d.time, end: event.time))
                }

            case .scroll(let dx, let dy):
                flushText()
                flushMove() // scrolling happens wherever the pointer is
                if let s = scroll, (event.time - s.end) * 1000 <= Double(options.scrollMergeGapMs) {
                    scroll = (s.dx + dx, s.dy + dy, s.start, event.time)
                } else {
                    flushScroll()
                    scroll = (dx, dy, event.time, event.time)
                }
            }
        }
        flushText()
        flushScroll()
        flushMove()
        // A button still held when recording stopped is dropped: half a click
        // would leave the button stuck down on playback.
        return out
    }
}
