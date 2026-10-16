import Foundation
import GlasspadKit
import GlasspadMacCore
import GlasspadMacros
import XCTest
@testable import Glasspad

/// The words the Mac shows. Always runs (unlike the snapshot drawings).
@MainActor
final class WordingTests: XCTestCase {
    func testGestureNamesAreHuman() {
        XCTAssertEqual(GestureNames.title(for: "fourFingerTap"), "Four-finger tap")
        XCTAssertEqual(GestureNames.title(for: "threeFingerDoubleTap"), "Three-finger double tap")
        // Not in the catalog: still no raw identifier on screen.
        XCTAssertEqual(GestureNames.title(for: "twoFingerLongPress"), "Two-finger long press")
        XCTAssertEqual(GestureNames.title(for: "shake"), "Shake")
        for g in GestureNames.catalog {
            XCTAssertFalse(g.title.contains(where: \.isUppercase) && g.title.dropFirst().contains(where: \.isUppercase),
                           g.title)
        }
    }

    /// Trackpad > If a Gesture Stops Working: plain words, and only gestures with a real choice.
    func testGestureOverrideWords() {
        XCTAssertEqual(GestureCopy.adjustable, [.magnify, .navigate, .spaces, .missionControl, .appExpose, .launchpad, .showDesktop])
        XCTAssertEqual(GesturePreference.allCases.map(GestureCopy.choice), ["Automatic", "Trackpad gesture", "Keyboard shortcut"])
        XCTAssertEqual(GestureCopy.diagnostics(.fallback, preference: .keyboardShortcut), "Keyboard shortcut, your choice")
        XCTAssertEqual(GestureCopy.diagnostics(.native, preference: .automatic), "Trackpad gesture")
        XCTAssertFalse(GestureCopy.footer.contains("native") || GestureCopy.footer.contains("private"))
    }

    func testKeyCaptions() {
        XCTAssertEqual(KeyCaption.caption(KeyCombo(.special(.space), [.command])), "⌘ Space")
        XCTAssertEqual(KeyCaption.caption(KeyCombo("t", [.command, .shift])), "⇧⌘ T")
        XCTAssertEqual(KeyCaption.caption(KeyCombo(.special(.returnKey))), "Return")
        XCTAssertEqual(KeyCaption.caption(KeyCombo(.special(.f5))), "F5")
        XCTAssertEqual(KeyCaption.caption(KeyCombo(.code(93))), "Recorded Key")
        // The picker names every special key in words, never its JSON name.
        for key in GlasspadMacros.SpecialKey.allCases {
            XCTAssertNotEqual(KeyCaption.name(key), key.rawValue, key.rawValue)
        }
    }

    func testStepSummariesHideBundleIDsAndCodes() {
        let name: (String) -> String = { $0 == "com.apple.Safari" ? "Safari" : "Other" }
        XCTAssertEqual(StepText.summary(.openApp(bundleID: "com.apple.Safari"), appName: name), "Open Safari")
        XCTAssertEqual(StepText.summary(.waitForApp(bundleID: "com.apple.Safari", timeoutMs: 5000), appName: name),
                       "Wait for Safari (up to 5 s)")
        XCTAssertEqual(StepText.summary(.keystroke(KeyCombo(.special(.space), [.command])), appName: name), "Press ⌘ Space")
        XCTAssertEqual(StepText.summary(.wait(ms: 500), appName: name), "Wait 500 ms")
        XCTAssertEqual(StepText.summary(.scroll(dx: 0, dy: -100), appName: name), "Scroll down 100")
        XCTAssertEqual(StepText.summary(.scroll(dx: 20, dy: 0), appName: name), "Scroll left 20")
        XCTAssertEqual(StepText.summary(.moveMouse(to: MacroPoint(x: 10, y: 20, reference: .frontWindow(.topRight))),
                                        appName: name), "Move pointer to 10, 20 from the window's top right")
        XCTAssertEqual(StepText.summary(.click(button: .right, at: .screen(5, 6), count: 2, modifiers: [.command]),
                                        appName: name), "Double-click right button holding ⌘ at 5, 6")
    }

    func testPairingWordsMatchThePhone() {
        // The phone's Settings button is "Pair a Mac"; its onboarding says "choose Pair Your iPhone".
        XCTAssertTrue(PairingCopy.instruction.contains("Pair a Mac"))
        XCTAssertEqual(PairingCopy.menuItem, "Pair Your iPhone…")
        XCTAssertTrue(PairingCopy.linkHelp.contains("Paste the Link Instead"))
        XCTAssertEqual(PairingCopy.heading(.paired(phoneName: "Soham's iPhone")), "Paired with Soham's iPhone")
        XCTAssertEqual(PairingCopy.showText, "Show Code as Text")
        XCTAssertEqual(PairingCopy.heading(.expired), "Code Expired")
    }

    func testPermissionsAreOrderedAndLabelled() throws {
        let model = AppModel(macName: "Mac", macros: try Fixtures.macros(), capabilities: .select { _ in true },
                             settings: .macDefault, actions: .init())
        model.accessibilityTrusted = false
        model.automation = .denied
        XCTAssertEqual(model.missingPermissions, [.accessibility, .automation])
        XCTAssertTrue(model.missingPermissions[0].isRequired)
        XCTAssertFalse(model.missingPermissions[1].isRequired)
        // Not asked yet is normal for the optional one, so it is not a "fix this" item.
        model.automation = .notDetermined
        XCTAssertEqual(model.missingPermissions, [.accessibility])
        model.accessibilityTrusted = true
        XCTAssertTrue(model.missingPermissions.isEmpty)
    }

    /// No em or en dashes in anything the Mac shows (house style).
    func testNoDashesInMacCopy() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Glasspad")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), file.lastPathComponent)
        }
    }
}
