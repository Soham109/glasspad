import Combine
import Foundation
import GlasspadKit
import XCTest
@testable import Glasspad

/// The menu bar icon redraws only when what it shows changes. Always runs.
@MainActor
final class MenuBarStatusTests: XCTestCase {
    func testIconChangesOnlyWithWhatItShows() throws {
        let model = AppModel(macName: "Mac", macros: try Fixtures.macros(), capabilities: .select { _ in true },
                             settings: .macDefault, actions: .init())
        model.link = .searching
        let status = MenuBarStatus(model: model)
        var looks: [MenuBarStatus.Look] = []
        let watch = status.$look.dropFirst().sink { looks.append($0) }
        defer { watch.cancel() }

        // Signal readings and other model changes leave the icon alone.
        var stats = LinkStats()
        stats.rttMedianMs = 4
        model.stats = stats
        model.lastError = "x"
        model.automation = .granted
        model.link = .searching
        XCTAssertTrue(looks.isEmpty)

        model.link = .connected(rttMs: nil)
        XCTAssertEqual(looks.last, .init(recording: false, paused: false, connected: true, title: "Connected"))
        model.isPaused = true
        XCTAssertEqual(looks.last, .init(recording: false, paused: true, connected: false, title: "Paused"))
        XCTAssertEqual(looks.count, 2)
        XCTAssertEqual(status.look.title, model.statusTitle)
    }

    /// The round trip inside `.connected` is dropped before it reaches the views.
    func testRoundTripIsLeftOutOfTheLinkState() {
        XCTAssertEqual(LinkState.connected(rttMs: 8.5).withoutRoundTrip, .connected(rttMs: nil))
        XCTAssertEqual(LinkState.searching.withoutRoundTrip, .searching)
    }
}
