import GlasspadKit
import QuartzCore
import UIKit

/// The raw multi-touch surface. Every touch sample, including the coalesced ones UIKit
/// collects between display frames, becomes one `TouchFrame` handed to `onFrame`
/// immediately. Nothing is batched to the display refresh.
///
/// Frames follow the kit contract: each lists every finger currently down, and a lifted
/// finger appears once with phase `ended` (or `cancelled`) before it disappears.
final class TrackpadSurfaceView: UIView {
    /// Called on the main thread for every sample, in time order.
    var onFrame: ((TouchFrame) -> Void)?
    /// Called on the first touch after the surface was dimmed. That touch only wakes the
    /// surface; it is not sent to the Mac.
    var onWake: (() -> Void)?

    var palette: Palette = .paper { didSet { applyPalette() } }
    var showsDots = true { didSet { if !showsDots { removeAllDots() } } }
    var isDimmed = false {
        didSet {
            guard isDimmed != oldValue else { return }
            UIView.animate(withDuration: isDimmed ? 1.2 : 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.dimView.alpha = self.isDimmed ? 0.6 : 0
            }
        }
    }

    private struct Finger {
        var touch: Touch
        var dot: CALayer?
    }

    private var idsByTouch: [ObjectIdentifier: UInt8] = [:]
    private var fingers: [UInt8: Finger] = [:]
    private var seq: UInt32 = 0
    /// True while the touches on screen started on a dimmed surface; they are ignored until all lift.
    private var swallowing = false
    private let dimView = UIView()
    private var dotImage: CGImage?

    static let dotSize: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = true
        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.isUserInteractionEnabled = false
        addSubview(dimView)
        applyPalette()
        isAccessibilityElement = true
        accessibilityLabel = "Trackpad"
        accessibilityHint = "Move one finger to move the pointer. Tap to click."
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimView.frame = bounds
    }

    private func applyPalette() {
        backgroundColor = palette.background
        dotImage = Self.renderDot(color: palette.dot)
        for finger in fingers.values { finger.dot?.contents = dotImage }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isDimmed, fingers.isEmpty {
            swallowing = true
            onWake?()
        }
        handle(touches, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { handle(touches, event: event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { handle(touches, event: event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { handle(touches, event: event) }

    private struct Sample {
        let key: ObjectIdentifier
        let timestamp: TimeInterval
        let location: CGPoint
        let phase: TouchPhase
        let radius: Double
    }

    private func handle(_ touches: Set<UITouch>, event: UIEvent?) {
        if swallowing {
            let stillDown = event?.allTouches?.contains { $0.phase != .ended && $0.phase != .cancelled } ?? false
            if !stillDown { swallowing = false }
            return
        }

        // Every sample of every changed finger, in time order.
        var samples: [Sample] = []
        samples.reserveCapacity(touches.count * 4)
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let phase = Self.phase(touch.phase)
            let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
            for (index, sample) in coalesced.enumerated() {
                // Only the last coalesced sample carries the real end; earlier ones are moves.
                let isLast = index == coalesced.count - 1
                let samplePhase: TouchPhase = isLast ? phase : (phase == .began ? .began : .moved)
                samples.append(Sample(key: key, timestamp: sample.timestamp,
                                      location: sample.location(in: self), phase: samplePhase,
                                      radius: Double(sample.majorRadius)))
            }
        }
        samples.sort { $0.timestamp < $1.timestamp }
        process(samples)
    }

    private func process(_ samples: [Sample]) {
        let size = bounds.size
        for sample in samples {
            let id: UInt8
            if let known = idsByTouch[sample.key] {
                id = known
            } else {
                guard sample.phase == .began || sample.phase == .moved, let free = freeID() else { continue }
                id = free
                idsByTouch[sample.key] = id
            }
            let x = min(max(Double(sample.location.x), 0), Double(size.width))
            let y = min(max(Double(sample.location.y), 0), Double(size.height))
            let isNew = fingers[id] == nil
            let phase: TouchPhase = isNew ? .began : (sample.phase == .began ? .moved : sample.phase)
            var finger = fingers[id] ?? Finger(touch: Touch(id: id, phase: .began, x: x, y: y), dot: nil)
            finger.touch = Touch(id: id, phase: phase, x: x, y: y, majorRadius: sample.radius)
            fingers[id] = finger

            emit(timestamp: sample.timestamp, size: size, changedID: id)

            if phase == .ended || phase == .cancelled {
                fadeOut(fingers[id]?.dot)
                fingers[id] = nil
                idsByTouch[sample.key] = nil
            }
        }
        updateDots()
    }

    /// Sends one frame with every finger. Fingers other than the one that changed are stationary.
    private func emit(timestamp: TimeInterval, size: CGSize, changedID: UInt8) {
        var list: [Touch] = []
        list.reserveCapacity(fingers.count)
        for (id, finger) in fingers {
            var t = finger.touch
            if id != changedID, t.phase == .began || t.phase == .moved { t.phase = .stationary }
            list.append(t)
        }
        list.sort { $0.id < $1.id }
        seq &+= 1
        onFrame?(TouchFrame(seq: seq, timestamp: timestamp, touches: list, surface: size))
    }

    private func freeID() -> UInt8? {
        let used = Set(fingers.keys)
        return (0...UInt8(250)).first { !used.contains($0) }
    }

    /// Lifts every finger (for example when the view leaves the screen mid touch) so the Mac
    /// never keeps a button held down.
    func cancelAllTouches() {
        guard !fingers.isEmpty else { return }
        for id in fingers.keys { fingers[id]?.touch.phase = .cancelled }
        seq &+= 1
        let list = fingers.values.map(\.touch).sorted { $0.id < $1.id }
        onFrame?(TouchFrame(seq: seq, timestamp: ProcessInfo.processInfo.systemUptime, touches: list, surface: bounds.size))
        removeAllDots()
        fingers = [:]
        idsByTouch = [:]
    }

    #if DEBUG
    /// Debug builds only: feeds scripted fingers through the same path real touches take
    /// (frames, haptics, dots). Used for simulator runs, which have no multi-touch input.
    func debugInject(_ fingers: [(key: NSObject, point: CGPoint, phase: TouchPhase)]) {
        let now = ProcessInfo.processInfo.systemUptime
        process(fingers.map { Sample(key: ObjectIdentifier($0.key), timestamp: now, location: $0.point,
                                     phase: $0.phase, radius: 20) })
    }
    #endif

    private static func phase(_ phase: UITouch.Phase) -> TouchPhase {
        switch phase {
        case .began: .began
        case .stationary: .stationary
        case .ended: .ended
        case .cancelled: .cancelled
        default: .moved
        }
    }

    // MARK: Dots

    private func updateDots() {
        guard showsDots else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, finger) in fingers {
            let dot: CALayer
            if let existing = finger.dot {
                dot = existing
            } else {
                dot = CALayer()
                dot.contents = dotImage
                dot.bounds = CGRect(x: 0, y: 0, width: Self.dotSize, height: Self.dotSize)
                dot.contentsScale = traitCollection.displayScale
                layer.insertSublayer(dot, below: dimView.layer)
                fingers[id]?.dot = dot
                dot.opacity = 1
            }
            dot.position = CGPoint(x: finger.touch.x, y: finger.touch.y)
        }
        CATransaction.commit()
    }

    private func fadeOut(_ dot: CALayer?) {
        guard let dot else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.28)
        CATransaction.setCompletionBlock { dot.removeFromSuperlayer() }
        dot.opacity = 0
        dot.transform = CATransform3DMakeScale(0.85, 0.85, 1)
        CATransaction.commit()
    }

    private func removeAllDots() {
        for id in fingers.keys {
            fingers[id]?.dot?.removeFromSuperlayer()
            fingers[id]?.dot = nil
        }
    }

    /// A 44 pt circle: solid centre, soft falloff over the outer third.
    private static func renderDot(color: UIColor) -> CGImage? {
        let format = UIGraphicsImageRendererFormat.preferred()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dotSize, height: dotSize), format: format)
        let image = renderer.image { ctx in
            let rgba = color.cgColor
            let clear = color.withAlphaComponent(0).cgColor
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: [rgba, rgba, clear] as CFArray,
                                            locations: [0, 0.62, 1]) else { return }
            let c = CGPoint(x: dotSize / 2, y: dotSize / 2)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c,
                                             endRadius: dotSize / 2, options: [])
        }
        return image.cgImage
    }
}
