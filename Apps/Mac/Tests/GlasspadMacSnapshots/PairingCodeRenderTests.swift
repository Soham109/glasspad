import AppKit
import GlasspadKit
import SwiftUI
import XCTest
@testable import Glasspad

/// Draws the Mac's real pairing view (glow, rounding, card and all) the way it is on screen,
/// and reads it back with the iPhone's Vision reader. Runs without GLASSPAD_SNAPSHOTS.
@MainActor
final class PairingCodeRenderTests: XCTestCase {
    func testTheLivingCodeReadsInLightAndDarkThroughItsMotion() throws {
        let message = Fixtures.pairingURL.absoluteString
        for dark in [false, true] {
            for size in [216.0, 260.0] {
                for t in stride(from: 0.0, through: 9.0, by: 1.5) {
                    let view = PairingCodeView(message: message, size: size, fixedTime: t)
                        .padding(24)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.cgImage)
                    XCTAssertEqual(PairingCodeReader.read(image)?.text, message, "dark \(dark), size \(size), t \(t)")
                }
            }
        }
    }
}
