import AppKit
import XCTest
@testable import Glasspad

/// The Allow question never answers Return: Allow needs a click, Escape is Don't Allow.
/// Always runs, and never shows a window.
@MainActor
final class ApprovalPromptTests: XCTestCase {
    func testReturnAnswersNothingAndEscapeIsDontAllow() {
        let (alert, allow, dontAllow) = ApprovalPrompt.makeAlert(phoneName: "Soham's iPhone")
        XCTAssertEqual(alert.buttons.count, 2)
        XCTAssertEqual(allow.title, ApprovalCopy.allow)
        XCTAssertEqual(allow.keyEquivalent, "")
        XCTAssertEqual(dontAllow.keyEquivalent, "\u{1b}")
        XCTAssertFalse(alert.buttons.contains { $0.keyEquivalent == "\r" })
    }
}
