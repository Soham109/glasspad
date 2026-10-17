import CoreGraphics
import Foundation

/// How Glasspad's keyboard fits the room it is given (the whole screen or one pane of a
/// layout): which style, how tall the keys are, and whether there is room for the strip of
/// shortcuts and the line of typed text above. Pure, so every pane size is tested.
public struct KeyboardPlan: Equatable, Sendable {
    public enum Fit: Equatable, Sendable {
        /// Every key fits.
        case full
        /// The short keyboard: a few keys left out, with a gentle note to make the pane taller.
        case short
        /// Too little room for keys you can hit: only the note and the iPhone keyboard button.
        case tooSmall
    }

    public var fit: Fit
    public var style: KeyboardStyle
    /// Rows of keys.
    public var rows: Int
    /// Row to row distance (a key plus the gap under it): every key is at least this tall to touch.
    public var pitch: CGFloat
    /// Height of the keys block, rows only.
    public var keysHeight: CGFloat { pitch * CGFloat(rows) - Self.gap }
    /// Height of the strip above the keys (shortcuts, esc on the wide keyboard, the iPhone
    /// keyboard button). 0 when there is no keyboard to sit on.
    public var stripHeight: CGFloat
    /// Room left above for the typed text, 0 when it does not fit.
    public var echoHeight: CGFloat
    /// Total height used, from the top of the strip to the bottom of the keys.
    public var keyboardHeight: CGFloat { (fit == .tooSmall ? 0 : keysHeight + Self.edge) + stripHeight }

    /// Space between keys, and between rows.
    public static let gap: CGFloat = 6
    /// Margin under the keys and at the sides.
    public static let edge: CGFloat = 4
    /// A key is never shorter than this to look at...
    public static let minKeyHeight: CGFloat = 36
    /// ...and with the gap, never less than this to touch (Apple's 44 pt).
    public static let minPitch: CGFloat = 44
    /// Keys stop growing here; extra room goes to the typed text.
    public static let maxPitch: CGFloat = 56
    public static let stripHeightValue: CGFloat = 44
    /// The typed text only shows with at least this much room.
    public static let minEcho: CGFloat = 52
    /// Panes at least this wide get the whole Mac keyboard.
    public static let wideWidth: CGFloat = 600

    public static func make(width: CGFloat, height: CGFloat) -> KeyboardPlan {
        let wide = width >= wideWidth
        let fullRows = 5
        let strip = stripHeightValue
        let available = height - strip - edge
        // The wide keyboard has five rows too, so the same heights decide both.
        if available + gap >= minPitch * CGFloat(fullRows) {
            let pitch = min(maxPitch, (available + gap) / CGFloat(fullRows))
            return finish(KeyboardPlan(fit: .full, style: wide ? .wide : .narrow, rows: fullRows, pitch: pitch,
                                       stripHeight: strip, echoHeight: 0), height: height)
        }
        if available + gap >= minPitch * 4 {
            // Wide but short (a landscape pane under a tall one): the narrow keyboard's short
            // form, which is complete enough to type and move around.
            let pitch = min(maxPitch, (available + gap) / 4)
            return finish(KeyboardPlan(fit: .short, style: .short, rows: 4, pitch: pitch,
                                       stripHeight: strip, echoHeight: 0), height: height)
        }
        return KeyboardPlan(fit: .tooSmall, style: .short, rows: 0, pitch: minPitch,
                            stripHeight: min(strip, max(0, height)), echoHeight: 0)
    }

    private static func finish(_ plan: KeyboardPlan, height: CGFloat) -> KeyboardPlan {
        var p = plan
        let left = height - p.keyboardHeight
        p.echoHeight = left >= minEcho ? left : 0
        return p
    }
}
