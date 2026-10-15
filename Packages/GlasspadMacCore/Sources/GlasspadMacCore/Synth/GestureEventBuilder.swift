import CoreGraphics

/// Builds the private gesture CGEvents. Pure: no posting, no state. Field numbers and their
/// sources are in CGSPrivate.swift.
public struct GestureEventBuilder {
    public let source: CGEventSource?

    public init(source: CGEventSource?) { self.source = source }

    private func gestureEvent(_ subtype: HIDEventType, at location: CGPoint) -> CGEvent? {
        guard let e = CGEvent(source: source) else { return nil }
        e.type = CGSEventKind.gesture.cgType
        e.location = location
        e.set(.gestureHIDType, subtype.rawValue)
        return e
    }

    /// Pinch to zoom: type 29, subtype Zoom (8), field 113 = magnification delta, 132 = phase.
    public func magnify(delta: Double, phase: HIDPhase, at location: CGPoint) -> CGEvent? {
        guard let e = gestureEvent(.zoom, at: location) else { return nil }
        e.set(.gestureZoomValue, double: delta)
        e.set(.gesturePhase, phase.rawValue)
        return e
    }

    /// Rotate: type 29, subtype Rotation (5), field 114 = degrees (positive counter-clockwise).
    public func rotate(degrees: Double, phase: HIDPhase, at location: CGPoint) -> CGEvent? {
        guard let e = gestureEvent(.rotation, at: location) else { return nil }
        e.set(.gestureRotationValue, double: degrees)
        e.set(.gesturePhase, phase.rawValue)
        return e
    }

    /// Smart zoom (two-finger double tap): type 29, subtype ZoomToggle (22), no other fields.
    public func smartMagnify(at location: CGPoint) -> CGEvent? {
        gestureEvent(.zoomToggle, at: location)
    }

    /// Navigation swipe (back/forward): a began event carrying the direction, then an ended
    /// event with direction none. Type 29, subtype NavigationSwipe (16), 115 = IOHIDSwipeMask.
    public func navigationSwipe(direction: HIDSwipe, at location: CGPoint) -> [CGEvent] {
        var out: [CGEvent] = []
        for (phase, dir) in [(HIDPhase.began, direction), (HIDPhase.ended, HIDSwipe.none)] {
            guard let e = gestureEvent(.navigationSwipe, at: location) else { return [] }
            e.set(.gesturePhase, phase.rawValue)
            e.set(.gestureSwipeValue, dir.rawValue)
            out.append(e)
        }
        return out
    }

    /// Dock swipe: a type-29 companion (field 41 = magic) followed by the type-30 dock-control
    /// event that carries the motion, cumulative origin offset, phase and exit speed.
    ///
    /// - originOffset: cumulative since the gesture began. Sign conventions, from [MMF] callers:
    ///   horizontal positive = towards the space on the right; vertical negative = Mission
    ///   Control (fingers up), positive = App Expose; pinch: see EventSynthesizer.
    /// - exitSpeed: only on ended/cancelled; written to both 129 and 130.
    public func dockSwipe(motion: DockSwipeMotion, originOffset: Double, phase: HIDPhase,
                          exitSpeed: Double?, invertedFromDevice: Bool, at location: CGPoint) -> [CGEvent] {
        guard let companion = CGEvent(source: source), let dock = CGEvent(source: source) else { return [] }
        companion.type = CGSEventKind.gesture.cgType
        companion.location = location
        companion.set(.dockSwipeCompanionMagic, dockSwipeCompanionMagicValue)

        dock.type = CGSEventKind.dockControl.cgType
        dock.location = location
        dock.set(.gestureHIDType, HIDEventType.dockSwipe.rawValue)
        dock.set(.gesturePhase, phase.rawValue)
        dock.set(.dockSwipePhaseRepeat, phase.rawValue)
        dock.set(.dockSwipeTypeEncodedA, double: motion.encoded)
        dock.set(.dockSwipeTypeEncodedB, double: motion.encoded)
        dock.set(.dockSwipeMotion, motion.rawValue)
        dock.set(.dockSwipeMotionRepeat, motion.rawValue)
        dock.set(.dockSwipeOriginOffset, double: originOffset)
        dock.set(.dockSwipeOriginOffsetBits, Int64(Float(originOffset).bitPattern))
        dock.set(.dockSwipeInvertedFromDevice, invertedFromDevice ? 1 : 0)
        if let exitSpeed {
            dock.set(.dockSwipeExitSpeedX, double: exitSpeed)
            dock.set(.dockSwipeExitSpeedY, double: exitSpeed)
        }
        return [companion, dock]
    }
}
