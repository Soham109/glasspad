import AppKit
import GlasspadKit

/// Present mode: arrow keys for slides and a soft laser dot drawn in a borderless, transparent,
/// click-through overlay window above everything (including full-screen presentations).
@MainActor
public final class PresentMode {
    private let keys: KeysMode
    private var overlay: LaserOverlay?

    /// Tests only: false keeps the overlay window off the screen and records into `laserLog`.
    var drawsOverlay = true
    /// Tests only: every show (true), hide (false) and move, in order, while `drawsOverlay` is off.
    private(set) var laserLog: [(visible: Bool, point: CGPoint?)] = []
    private var laserStarted = false

    public init(keys: KeysMode) { self.keys = keys }

    public func next() { keys.press(KeyStroke(.right)) }
    public func previous() { keys.press(KeyStroke(.left)) }

    public func setLaser(on: Bool) {
        if on { laserStarted = true }
        guard drawsOverlay else { return laserLog.append((on, nil)) }
        if on {
            if overlay == nil { overlay = LaserOverlay() }
            overlay?.show()
        } else {
            overlay?.hide()
        }
    }

    /// Normalized 0...1 across the main display, origin top left.
    public func moveLaser(x: Double, y: Double) {
        if !laserStarted { setLaser(on: true) }
        let point = Self.screenPoint(x: x, y: y, screen: NSScreen.screens.first?.frame ?? .zero)
        guard drawsOverlay else { return laserLog.append((true, point)) }
        overlay?.move(to: point)
    }

    /// Converts normalized top-left coordinates to AppKit (bottom-left origin) screen points.
    public nonisolated static func screenPoint(x: Double, y: Double, screen: CGRect) -> CGPoint {
        let cx = min(1, max(0, x)), cy = min(1, max(0, y))
        return CGPoint(x: screen.minX + cx * screen.width, y: screen.maxY - cy * screen.height)
    }
}

@MainActor
final class LaserOverlay {
    private let window: NSPanel
    private let dot = LaserDotView()

    init() {
        let frame = NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        window.contentView = content
        content.addSubview(dot)
        dot.isHidden = true
    }

    func show() {
        if let frame = NSScreen.screens.first?.frame { window.setFrame(frame, display: false) }
        window.orderFrontRegardless()
    }

    func hide() {
        dot.isHidden = true
        window.orderOut(nil)
    }

    func move(to screenPoint: CGPoint) {
        let local = CGPoint(x: screenPoint.x - window.frame.minX, y: screenPoint.y - window.frame.minY)
        let size = LaserDotView.diameter + LaserDotView.glow * 2
        dot.frame = NSRect(x: local.x - size / 2, y: local.y - size / 2, width: size, height: size)
        dot.isHidden = false
        if !window.isVisible { show() }
    }
}

/// A soft red dot: solid core with a blurred glow from a layer shadow.
final class LaserDotView: NSView {
    static let diameter: CGFloat = 18
    static let glow: CGFloat = 14

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let core = CALayer()
        core.backgroundColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
        core.cornerRadius = Self.diameter / 2
        core.frame = CGRect(x: Self.glow, y: Self.glow, width: Self.diameter, height: Self.diameter)
        core.shadowColor = NSColor.systemRed.cgColor
        core.shadowOpacity = 0.8
        core.shadowRadius = Self.glow / 2
        core.shadowOffset = .zero
        layer?.addSublayer(core)
    }

    required init?(coder: NSCoder) { nil }
}
