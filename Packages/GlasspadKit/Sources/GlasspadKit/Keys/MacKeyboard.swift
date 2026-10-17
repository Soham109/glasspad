import CoreGraphics
import Foundation

/// One key on Glasspad's own keyboard.
public enum KeyboardKeyKind: Equatable, Sendable, Hashable {
    /// A character key of the Mac's layout, by position (see `KeyboardLetters`).
    case character(UInt16)
    /// Esc, Tab, Delete, Return, Space, the arrows and the F-keys.
    case special(SpecialKey)
    /// Shift, Control, Option, Command or fn (`KeyModifiers.function`).
    case modifier(KeyModifiers)
    case capsLock
    /// Switches the narrow keyboard between letters and numbers with symbols.
    case symbols

    /// Held down, the key presses again and again, like the Mac's own repeat. Characters do not
    /// repeat: on glass a held letter is a slow tap, not a request for "aaaa".
    public var repeats: Bool {
        switch self {
        case .special(let s): [.delete, .forwardDelete, .left, .right, .up, .down, .space].contains(s)
        default: false
        }
    }

    /// Sends something to the Mac (as opposed to changing the keyboard itself).
    public var types: Bool {
        switch self {
        case .character, .special: true
        default: false
        }
    }
}

/// A key and its place in a row. `width` is in key units (a letter key is 1).
public struct KeyboardKey: Equatable, Sendable, Hashable, Identifiable {
    public var kind: KeyboardKeyKind
    public var width: Double
    /// Which modifier key this is when a row has two (left and right Shift, Command, Option).
    public var side: Int

    public var id: String {
        switch kind {
        case .character(let c): "c\(c)"
        case .special(let s): "s\(s.rawValue)"
        case .modifier(let m): "m\(m.rawValue).\(side)"
        case .capsLock: "caps"
        case .symbols: "symbols"
        }
    }

    public init(_ kind: KeyboardKeyKind, width: Double = 1, side: Int = 0) {
        self.kind = kind
        self.width = width
        self.side = side
    }
}

/// One row: keys side by side. A `stack` slot holds two half-height keys one over the other
/// (the up and down arrows of a Mac keyboard).
public struct KeyboardRow: Equatable, Sendable {
    public enum Slot: Equatable, Sendable {
        case key(KeyboardKey)
        case stack(KeyboardKey, KeyboardKey)
        /// Empty room, in key units (the half-key indent of the narrow home row).
        case space(Double)

        public var width: Double {
            switch self {
            case .key(let k): k.width
            case .stack(let a, _): a.width
            case .space(let w): w
            }
        }
    }

    public var slots: [Slot]
    public init(_ slots: [Slot]) { self.slots = slots }

    public var units: Double { slots.reduce(0) { $0 + $1.width } }
    public var keys: [KeyboardKey] {
        slots.flatMap { slot -> [KeyboardKey] in
            switch slot {
            case .key(let k): [k]
            case .stack(let a, let b): [a, b]
            case .space: []
            }
        }
    }
}

/// The shapes Glasspad's keyboard comes in.
public enum KeyboardStyle: String, Equatable, Sendable {
    /// A whole Mac keyboard: number row, Tab, Caps Lock, both Shifts, the Mac bottom row with
    /// inverted-T arrows. Needs a wide pane (landscape).
    case wide
    /// Phone width: ten keys across like the iPhone keyboard, numbers and symbols one tap away,
    /// and a row of Mac keys (esc, tab, fn, arrows) under the space bar.
    case narrow
    /// A short pane: the narrow keyboard without its row of Mac keys. esc, Command and the
    /// arrows move into the space bar row; Tab, Control, Option and fn need a taller pane.
    case short
}

/// The rows of Glasspad's keyboard for a style and its current state. Pure: the view draws
/// what this returns, and touches are matched against the same rows.
public enum MacKeyboard {
    /// What the keyboard shows right now.
    public struct Options: Equatable, Sendable {
        /// Narrow and short only: the numbers and symbols page instead of letters.
        public var symbols = false
        /// fn is on: the top row becomes F1 to F12.
        public var functionKeys = false
        public init(symbols: Bool = false, functionKeys: Bool = false) {
            self.symbols = symbols
            self.functionKeys = functionKeys
        }
    }

    static let fKeys: [SpecialKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]

    public static func rows(_ style: KeyboardStyle, _ options: Options = Options()) -> [KeyboardRow] {
        switch style {
        case .wide: wideRows(options)
        case .narrow: narrowRows(options, short: false)
        case .short: narrowRows(options, short: true)
        }
    }

    private static func ch(_ codes: [UInt16]) -> [KeyboardRow.Slot] { codes.map { .key(KeyboardKey(.character($0))) } }
    private static func k(_ kind: KeyboardKeyKind, _ width: Double = 1, side: Int = 0) -> KeyboardRow.Slot {
        .key(KeyboardKey(kind, width: width, side: side))
    }

    /// A Mac keyboard's five rows, 14.5 units each.
    private static func wideRows(_ o: Options) -> [KeyboardRow] {
        let top: KeyboardRow
        if o.functionKeys {
            // Like holding fn on a Touch Bar Mac: the number row turns into the F-keys.
            top = KeyboardRow([k(.special(.escape), 1)] + fKeys.map { k(.special($0), 12.0 / 12) }
                              + [k(.special(.delete), 1.5)])
        } else {
            top = KeyboardRow(ch(KeyboardLetters.numberRow) + [k(.special(.delete), 1.5)])
        }
        return [
            top,
            KeyboardRow([k(.special(.tab), 1.5)] + ch(KeyboardLetters.topRow)),
            KeyboardRow([k(.capsLock, 1.75)] + ch(KeyboardLetters.homeRow) + [k(.special(.returnKey), 1.75)]),
            KeyboardRow([k(.modifier(.shift), 2.25)] + ch(KeyboardLetters.bottomRow) + [k(.modifier(.shift), 2.25, side: 1)]),
            KeyboardRow([k(.modifier(.function)), k(.modifier(.control)), k(.modifier(.option)), k(.modifier(.command), 1.25),
                         k(.special(.space), 5),
                         k(.modifier(.command), 1.25, side: 1), k(.modifier(.option), 1, side: 1),
                         k(.special(.left)),
                         .stack(KeyboardKey(.special(.up)), KeyboardKey(.special(.down))),
                         k(.special(.right))]),
        ]
    }

    /// Ten units across, like the iPhone keyboard. The key for the iPhone keyboard sits on the
    /// strip above every style, not in the rows.
    private static func narrowRows(_ o: Options, short: Bool) -> [KeyboardRow] {
        var rows: [KeyboardRow]
        let shiftRowEnd: [KeyboardRow.Slot] = [k(.special(.delete), 1.5)]
        if o.symbols {
            // Numbers, then every punctuation key of the Mac's layout. Shift gives each key's
            // other character, the way it does on the Mac.
            rows = [
                KeyboardRow(ch(Array(KeyboardLetters.numberRow[1...10]))),
                KeyboardRow(ch([50, 27, 24, 33, 30, 42, 41, 39]).map { widen($0, 10.0 / 8) }),
                KeyboardRow([k(.modifier(.shift), 1.5)] + ch([43, 47, 44]).map { widen($0, 7.0 / 3) } + shiftRowEnd),
            ]
        } else {
            rows = [
                KeyboardRow(ch(Array(KeyboardLetters.topRow[0..<10]))),
                KeyboardRow([.space(0.5)] + ch(Array(KeyboardLetters.homeRow[0..<9])) + [.space(0.5)]),
                KeyboardRow([k(.modifier(.shift), 1.5)] + ch(Array(KeyboardLetters.bottomRow[0..<7])) + shiftRowEnd),
            ]
        }
        if o.functionKeys {
            rows[0] = KeyboardRow(fKeys.map { k(.special($0), 10.0 / 12) })
        }
        if short {
            // No room for the row of Mac keys: esc, Command and the arrows join the space bar.
            rows.append(KeyboardRow([k(.symbols, 1.25), k(.special(.escape)), k(.modifier(.command)),
                                     k(.special(.space), 2.75), k(.special(.left)),
                                     .stack(KeyboardKey(.special(.up)), KeyboardKey(.special(.down))),
                                     k(.special(.right)), k(.special(.returnKey))]))
        } else {
            rows.append(KeyboardRow([k(.symbols, 1.5), k(.modifier(.control)), k(.modifier(.option)), k(.modifier(.command), 1.25),
                                     k(.special(.space), 3.25), k(.special(.returnKey), 2)]))
            rows.append(KeyboardRow([k(.special(.escape)), k(.special(.tab)), k(.modifier(.function)), .space(3),
                                     k(.special(.left)), k(.special(.up)), k(.special(.down)), k(.special(.right))]))
        }
        return rows
    }

    private static func widen(_ slot: KeyboardRow.Slot, _ width: Double) -> KeyboardRow.Slot {
        guard case .key(var key) = slot else { return slot }
        key.width = width
        return .key(key)
    }

    // MARK: Geometry

    /// A key and where it is drawn.
    public struct PlacedKey: Equatable, Sendable {
        public var key: KeyboardKey
        public var frame: CGRect
        public var row: Int
    }

    /// Lays `rows` out in `size`: every row the same height, keys spread over the full width
    /// in proportion to their units, `gap` between keys and rows. Rows narrower than the widest
    /// are centred.
    public static func place(_ rows: [KeyboardRow], in size: CGSize, gap: CGFloat) -> [PlacedKey] {
        guard !rows.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let units = rows.map(\.units).max() ?? 1
        let pitch = (size.height + gap) / CGFloat(rows.count)
        let keyHeight = pitch - gap
        let unit = (size.width + gap) / CGFloat(units)
        var out: [PlacedKey] = []
        for (r, row) in rows.enumerated() {
            var x = (CGFloat(units - row.units) * unit) / 2
            let y = CGFloat(r) * pitch
            for slot in row.slots {
                let w = CGFloat(slot.width) * unit - gap
                switch slot {
                case .key(let key):
                    out.append(PlacedKey(key: key, frame: CGRect(x: x, y: y, width: w, height: keyHeight), row: r))
                case .stack(let a, let b):
                    let h = (keyHeight - gap / 2) / 2
                    out.append(PlacedKey(key: a, frame: CGRect(x: x, y: y, width: w, height: h), row: r))
                    out.append(PlacedKey(key: b, frame: CGRect(x: x, y: y + h + gap / 2, width: w, height: h), row: r))
                case .space:
                    break
                }
                x += CGFloat(slot.width) * unit
            }
        }
        return out
    }

    /// The key a touch at `point` means: the key under it, or the nearest key in its row, so
    /// the gaps between keys and the empty ends of a row still type. nil outside the keyboard.
    public static func key(at point: CGPoint, in placed: [PlacedKey], gap: CGFloat) -> PlacedKey? {
        guard let first = placed.first else { return nil }
        let reach = gap / 2 + 0.5
        if let hit = placed.first(where: { $0.frame.insetBy(dx: -reach, dy: -reach).contains(point) }) { return hit }
        // Nearest row first (by vertical distance), then the nearest key in it.
        func distance(_ r: CGRect, _ p: CGPoint) -> CGFloat {
            let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
            return (dx * dx + dy * dy).squareRoot()
        }
        let bounds = placed.reduce(first.frame) { $0.union($1.frame) }.insetBy(dx: -reach, dy: -reach)
        guard bounds.contains(point) else { return nil }
        return placed.min { distance($0.frame, point) < distance($1.frame, point) }
    }
}
