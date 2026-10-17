import CoreGraphics

/// How wide a scrolling row of chips shows itself so that, at rest, it holds only whole chips
/// (Keyboard's shortcut row): from the chip at the front, as many as fit in `room`. The room
/// left over stays empty, so the last chip never runs under whatever sits after the row.
public enum ChipWindow {
    /// `widths` are the chips' widths in order, `from` the one at the front. Until every chip
    /// has been measured (a width of 0), or when not even one fits, the row takes all the room.
    public static func width(widths: [CGFloat], from: Int, spacing: CGFloat, room: CGFloat) -> CGFloat {
        guard room > 0, !widths.isEmpty, widths.allSatisfy({ $0 > 0 }) else { return max(0, room) }
        let start = min(max(0, from), widths.count - 1)
        var used: CGFloat = 0
        var count = 0
        for w in widths[start...] {
            let next = used + (count == 0 ? 0 : spacing) + w
            if next > room { break }
            used = next
            count += 1
        }
        return count == 0 ? room : used
    }

    /// When the chips do not all fit, the width to add to each one so the first screenful fills
    /// the room exactly, like a row of keys, rather than ending in a gap. Zero when all fit.
    public static func stretch(widths: [CGFloat], spacing: CGFloat, room: CGFloat) -> CGFloat {
        guard room > 0, !widths.isEmpty, widths.allSatisfy({ $0 > 0 }) else { return 0 }
        let all = widths.reduce(0, +) + spacing * CGFloat(widths.count - 1)
        guard all > room else { return 0 }
        var used: CGFloat = 0
        var count = 0
        for w in widths {
            let next = used + (count == 0 ? 0 : spacing) + w
            if next > room { break }
            used = next
            count += 1
        }
        guard count > 0 else { return 0 }
        return ((room - used) / CGFloat(count)).rounded(.down)
    }
}
