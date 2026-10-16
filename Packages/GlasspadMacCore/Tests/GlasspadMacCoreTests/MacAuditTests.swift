import AppKit
import CoreGraphics
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Fixes from checking every Mac control against this macOS (read only).
@MainActor
@Suite struct MacAuditTests {
    /// Mission Control's program is SIGKILLed when started directly, so its fallback goes
    /// through Launch Services.
    @Test func missionControlStartsThroughLaunchServices() {
        let desktop = DeckMode.missionControlLaunch("1")
        #expect(desktop.path == "/usr/bin/open")
        #expect(desktop.arguments == ["-g", "-b", "com.apple.exposelauncher", "--args", "1"])
        #expect(DeckMode.missionControlLaunch(nil).arguments == ["-g", "-b", "com.apple.exposelauncher"])
    }

    /// A MacBook with an external display as main: the buttons change the built-in display,
    /// as the brightness keys do, instead of failing.
    @Test func brightnessButtonsFallBackToTheBuiltInDisplay() {
        let main: CGDirectDisplayID = 5, builtIn: CGDirectDisplayID = 1
        #expect(Brightness.buttonDisplay(main: main, builtIn: builtIn, readable: { _ in true }) == main)
        #expect(Brightness.buttonDisplay(main: main, builtIn: builtIn, readable: { $0 == builtIn }) == builtIn)
        #expect(Brightness.buttonDisplay(main: main, builtIn: nil, readable: { $0 == builtIn }) == nil)
        #expect(Brightness.buttonDisplay(main: main, builtIn: builtIn, readable: { _ in false }) == nil)
        #expect(Brightness.buttonDisplay(main: builtIn, builtIn: builtIn, readable: { _ in false }) == nil)
    }

    /// Pasteboard access set to Deny reads as empty; the phone is told why instead.
    @Test func deniedPasteboardSaysWhy() async {
        let pb = NSPasteboard(name: NSPasteboard.Name("glasspad-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("hello", forType: .string)
        let clip = ClipboardMode(pasteboard: pb)
        #expect(await clip.pullResult() == .content(.text("hello")))
        clip.accessDenied = { _ in true }
        #expect(await clip.pullResult() == .notAllowed)
        #expect(clip.lastRefusal == ClipboardLimits.notAllowed)
        #expect(await clip.pull() == nil)
        // A named pasteboard is never denied by macOS.
        #expect(!ClipboardMode.readsDenied(pb))
    }
}
