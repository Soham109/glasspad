import AppKit

/// A soft outline in the accent colour around one window for about a second, so the person
/// sees on the Mac which window they picked on the phone. Drawn in a borderless, transparent,
/// click-through panel above the window (like Present's laser): it never activates Glasspad,
/// moves a window or brings one forward. With Reduce Motion it appears and goes without a fade.
@MainActor
final class WindowHighlight {
    private let panel: NSPanel
    private let ring = HighlightRingView()
    private var generation = 0

    /// How long the outline stays, fades included.
    static let duration: TimeInterval = 1
    /// Room outside the window for the ring and its glow.
    static let outset: CGFloat = 8

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = ring
    }

    /// `frame` in global display coordinates (Quartz: top-left origin, y down).
    func show(around frame: CGRect) {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let target = Self.appKitFrame(frame, mainHeight: mainHeight).insetBy(dx: -Self.outset, dy: -Self.outset)
        generation += 1
        let mine = generation
        panel.setFrame(target, display: true)
        ring.needsDisplay = true
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fade = still ? 0 : 0.2
        panel.alphaValue = still ? 1 : 0
        panel.orderFrontRegardless()
        if !still {
            NSAnimationContext.runAnimationGroup { $0.duration = fade; panel.animator().alphaValue = 1 }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.duration - fade))
            guard let self, self.generation == mine else { return }
            if still { return self.panel.orderOut(nil) }
            NSAnimationContext.runAnimationGroup({ $0.duration = fade; self.panel.animator().alphaValue = 0 }) {
                MainActor.assumeIsolated { if self.generation == mine { self.panel.orderOut(nil) } }
            }
        }
    }

    /// Quartz global coordinates to AppKit's (bottom-left origin of the main display, y up).
    nonisolated static func appKitFrame(_ quartz: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: quartz.minX, y: mainHeight - quartz.maxY, width: quartz.width, height: quartz.height)
    }
}

/// The ring: the window's rounded outline in the accent colour with a soft glow.
private final class HighlightRingView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let inset = WindowHighlight.outset - 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
        path.lineWidth = 4
        let accent = NSColor.controlAccentColor
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = accent.withAlphaComponent(0.6)
        glow.shadowBlurRadius = 6
        glow.set()
        accent.withAlphaComponent(0.9).setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
