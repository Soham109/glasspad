import GlasspadKit
import QuartzCore
import UIKit

/// The raw multi-touch surface. Each touch callback from UIKit (one per display frame, 120 Hz
/// on ProMotion with `CADisableMinimumFrameDurationOnPhone`) becomes one `TouchFrame` with the
/// newest position of every finger, stamped with the newest sample's time, handed to `onFrame`
/// at once. The coalesced samples in between still update the finger positions in time order,
/// but they are not sent one by one: that sent a burst of 2 to 6 packets per callback (one per
/// sample and per finger, 430 to 700 a second measured on the Mac), which only added air time
/// and bunching. The Mac spreads motion evenly between frame timestamps itself.
///
/// A frame is also sent at the moment a finger lifts, so a tap that begins and ends inside one
/// callback still shows both phases.
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

    /// The size the fingers on screen were measured against.
    private var surfaceSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        dimView.frame = bounds
        guard bounds.size != surfaceSize else { return }
        // The surface turned (or resized) under the fingers. Their coordinates no longer
        // mean the same thing, so lift them all, measured against the old size, and ignore
        // those touches until they leave the glass. The next touch starts clean.
        if !fingers.isEmpty {
            cancelAllTouches()
            swallowing = true
        }
        surfaceSize = bounds.size
    }

    private func applyPalette() {
        backgroundColor = palette.background
        dotImage = Self.renderDot(color: palette.dot, size: palette.dotDiameter, style: palette.dotStyle)
        let side = palette.dotDiameter
        for finger in fingers.values {
            finger.dot?.contents = dotImage
            finger.dot?.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        }
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
        stats.callback()
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
        // Coordinates are in this view's space, which UIKit keeps upright in every
        // orientation: toward the top of the phone as held is always negative y.
        let size = bounds.size
        var unsent: TimeInterval?
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
            var phase: TouchPhase = isNew ? .began : (sample.phase == .began ? .moved : sample.phase)
            // A finger stays `began` until a frame carrying it has been sent.
            if !isNew, phase == .moved, fingers[id]?.touch.phase == .began { phase = .began }
            var finger = fingers[id] ?? Finger(touch: Touch(id: id, phase: .began, x: x, y: y), dot: nil)
            finger.touch = Touch(id: id, phase: phase, x: x, y: y, majorRadius: sample.radius)
            fingers[id] = finger
            changed.insert(id)
            stats.sample()

            if phase == .ended || phase == .cancelled {
                emit(timestamp: sample.timestamp, size: size)
                unsent = nil
                fadeOut(fingers[id]?.dot)
                fingers[id] = nil
                idsByTouch[sample.key] = nil
            } else {
                unsent = sample.timestamp
            }
        }
        if let t = unsent { emit(timestamp: t, size: size) }
        updateDots()
        if fingers.isEmpty { stats.end() }
    }

    /// Fingers that changed since the last frame was sent; the rest are sent as stationary.
    private var changed: Set<UInt8> = []
    private var stats = TouchRateStats()

    /// Sends one frame with every finger. Fingers that did not change since the last frame are
    /// stationary. A finger that began counts as began until it has been sent once.
    private func emit(timestamp: TimeInterval, size: CGSize) {
        var list: [Touch] = []
        list.reserveCapacity(fingers.count)
        for (id, finger) in fingers {
            var t = finger.touch
            if !changed.contains(id), t.phase == .began || t.phase == .moved { t.phase = .stationary }
            list.append(t)
            if t.phase == .began { fingers[id]?.touch.phase = .moved }
        }
        changed = []
        list.sort { $0.id < $1.id }
        seq &+= 1
        stats.frame()
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
        let size = surfaceSize == .zero ? bounds.size : surfaceSize
        onFrame?(TouchFrame(seq: seq, timestamp: ProcessInfo.processInfo.systemUptime, touches: list, surface: size))
        removeAllDots()
        fingers = [:]
        idsByTouch = [:]
        changed = []
        stats.end()
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
                dot.bounds = CGRect(x: 0, y: 0, width: palette.dotDiameter, height: palette.dotDiameter)
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

    /// One finger dot in the user's style (Settings > Finger Dots): soft (solid centre, soft
    /// edge over the outer third, as designed), solid, or a ring. Size in points.
    private static func renderDot(color: UIColor, size: CGFloat, style: DotStyle) -> CGImage? {
        let format = UIGraphicsImageRendererFormat.preferred()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            switch style {
            case .soft:
                let rgba = color.cgColor
                let clear = color.withAlphaComponent(0).cgColor
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgba, rgba, clear] as CFArray,
                                                locations: [0, 0.62, 1]) else { return }
                let c = CGPoint(x: size / 2, y: size / 2)
                cg.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size / 2, options: [])
            case .solid:
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: rect.insetBy(dx: size * 0.1, dy: size * 0.1))
            case .ring:
                let w = max(2, size * 0.07)
                cg.setStrokeColor(color.withAlphaComponent(min(1, color.cgColor.alpha * 2.2)).cgColor)
                cg.setLineWidth(w)
                cg.strokeEllipse(in: rect.insetBy(dx: w / 2, dy: w / 2))
            }
        }
        return image.cgImage
    }
}

/// Counts what the surface sees and sends during one touch session (first finger down to last
/// finger up) and logs it, so the phone's real touch rate can be read from the console:
/// `touch rate: 1.84 s, 221 callbacks (120/s), 442 samples (240/s), 223 frames sent (121/s)`.
struct TouchRateStats {
    private var start: TimeInterval?
    private var callbacks = 0, samples = 0, frames = 0

    mutating func callback() {
        if start == nil { start = ProcessInfo.processInfo.systemUptime }
        callbacks += 1
    }
    mutating func sample() { samples += 1 }
    mutating func frame() { frames += 1 }

    mutating func end() {
        guard let s = start else { return }
        let d = ProcessInfo.processInfo.systemUptime - s
        start = nil
        defer { callbacks = 0; samples = 0; frames = 0 }
        guard d > 0.25 else { return }
        func rate(_ n: Int) -> Int { Int((Double(n) / d).rounded()) }
        GPLog.log(String(format: "touch rate: %.2f s, ", d)
            + "\(callbacks) callbacks (\(rate(callbacks))/s), \(samples) samples (\(rate(samples))/s), "
            + "\(frames) frames sent (\(rate(frames))/s)")
    }
}
