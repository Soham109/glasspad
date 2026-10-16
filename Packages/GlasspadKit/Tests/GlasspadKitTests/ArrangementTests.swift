import CoreGraphics
import Testing
@testable import GlasspadKit

@Suite struct ArrangementTests {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func onlyOnePieceDesksAreReachable() {
        let right = CGRect(x: 1512, y: -458, width: 2560, height: 1440)
        #expect(DisplayGeometry.isReachableArrangement([laptop]))
        #expect(DisplayGeometry.isReachableArrangement([laptop, right]))
        // Three in a row: the far one is reached through the middle one.
        #expect(DisplayGeometry.isReachableArrangement([laptop, right, CGRect(x: 4072, y: 0, width: 1920, height: 1080)]))
        // A gap, a corner only, an overlap, nothing at all.
        #expect(!DisplayGeometry.isReachableArrangement([laptop, CGRect(x: 1600, y: 0, width: 1920, height: 1080)]))
        #expect(!DisplayGeometry.isReachableArrangement([laptop, CGRect(x: 1512, y: 982, width: 1920, height: 1080)]))
        #expect(!DisplayGeometry.isReachableArrangement([laptop, CGRect(x: 1000, y: 0, width: 1920, height: 1080)]))
        #expect(!DisplayGeometry.isReachableArrangement([]))
        // Numbers no desk has, or no number at all.
        #expect(!DisplayGeometry.isReachableArrangement([laptop, CGRect(x: 1512, y: 0, width: 1e12, height: 1080)]))
        #expect(!DisplayGeometry.isReachableArrangement([laptop, CGRect(x: CGFloat.nan, y: 0, width: 1920, height: 1080)]))
        #expect(!DisplayGeometry.isReachableArrangement([CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)]))
    }

    @Test func aWindowMoveWithNoNumberIsRefused() {
        let s = DisplaysState(displays: [MacDisplay(id: 1, name: "A", frame: laptop, visibleFrame: laptop, isMain: true)],
                              windows: [MacWindow(id: 9, bundleID: nil, appName: "App", frame: CGRect(x: 10, y: 10, width: 100, height: 100))])
        #expect(s.frames(for: .move(display: 1, origin: CGPoint(x: CGFloat.nan, y: 0)), window: 9) == nil)
        #expect(s.frames(for: .move(display: 1, origin: CGPoint(x: 5, y: 5)), window: 9)?.first?.frame == CGRect(x: 5, y: 5, width: 100, height: 100))
    }
}
