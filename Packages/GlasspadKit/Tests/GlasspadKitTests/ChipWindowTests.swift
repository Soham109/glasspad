import CoreGraphics
import Testing
@testable import GlasspadKit

@Suite struct ChipWindowTests {
    private let chips: [CGFloat] = [80, 90, 85, 70, 120, 140, 110]

    @Test func everythingFitsShowsTheWholeRow() {
        let total = chips.reduce(0, +) + 6 * CGFloat(chips.count - 1)
        #expect(ChipWindow.width(widths: chips, from: 0, spacing: 6, room: 1000) == total)
    }

    @Test func aNarrowRowEndsOnAWholeChip() {
        // 80 + 6 + 90 + 6 + 85 = 267; the next one (70) would need 343.
        #expect(ChipWindow.width(widths: chips, from: 0, spacing: 6, room: 330) == 267)
        // Scrolled on: starts at the fourth chip.
        #expect(ChipWindow.width(widths: chips, from: 3, spacing: 6, room: 330) == 196)
    }

    @Test func unknownWidthsOrOneHugeChipTakeAllTheRoom() {
        #expect(ChipWindow.width(widths: [80, 0, 90], from: 0, spacing: 6, room: 300) == 300)
        #expect(ChipWindow.width(widths: [400, 80], from: 0, spacing: 6, room: 300) == 300)
        #expect(ChipWindow.width(widths: [], from: 0, spacing: 6, room: 300) == 300)
        #expect(ChipWindow.width(widths: chips, from: 99, spacing: 6, room: 300) == 110)
        #expect(ChipWindow.width(widths: chips, from: 0, spacing: 6, room: -5) == 0)
    }

    @Test func aFirstScreenfulStretchesToFillTheRoom() {
        // Three fit in 330 (267 used): 63 left, 21 more each.
        let extra = ChipWindow.stretch(widths: chips, spacing: 6, room: 330)
        #expect(extra == 21)
        let stretched = chips.map { $0 + extra }
        #expect(ChipWindow.width(widths: stretched, from: 0, spacing: 6, room: 330) == 330)
        // Everything fits: nothing stretches.
        #expect(ChipWindow.stretch(widths: chips, spacing: 6, room: 2000) == 0)
        #expect(ChipWindow.stretch(widths: [80, 0], spacing: 6, room: 100) == 0)
    }
}
