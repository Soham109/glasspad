import CoreGraphics

// Private CoreGraphics event vocabulary used to synthesize real trackpad gestures.
//
// Nothing in this file is public API. Every number is written out once, named, and
// tagged with where it comes from. Tags:
//
//   [HID]  Apple's open-source IOHIDFamily, IOHIDEventTypes.h (rel/IOHIDFamily-1035), the
//          enums IOHIDEventType, IOHIDEventPhaseBits and IOHIDSwipeMask. These are Apple's own
//          published values, so they are VERIFIED.
//   [CT]   Calf Trail "TouchSynthesis" (Nathan Vander Wilt, 2010), TouchEvents.c, which builds
//          gesture events field by field: 0x6E subtype, 0x84 phase, 0x71 magnification,
//          0x72 rotation, 0x73 swipe direction, 0x75 next subtype. Read for facts only; it is
//          GPL, no code taken.
//   [MMF]  Mac Mouse Fix 3 (Noah Nuebling), Helper/Core/Touch/TouchSimulator.m and its callers
//          (ModifiedDragOutputThreeFingerSwipe.m, Scroll.m, Actions.m). Read for facts only;
//          it is under the MMF License, which is not MIT compatible, so no code taken.
//   [CG]   Public CoreGraphics headers (CGEventTypes.h), named here for completeness.
//
// Two independent sources agreeing on a number is marked VERIFIED. A number seen in only one
// source, or whose meaning is not understood, is marked ASSUMED.
//
// Swift note: CGEventType/CGEventField are imported C enums, so `init(rawValue:)` accepts
// values that have no named case. That is how the private numbers are reached.

/// Private CGEvent types (values of the event type field, kCGSEventTypeField = 55).
public enum CGSEventKind: UInt32, Sendable {
    /// NSEventTypeGesture. Carries magnify/rotate/swipe/smart magnify via the HID subtype
    /// field. VERIFIED: [MMF] posts type 29 for all of them; NSEvent.EventType.gesture is 29
    /// in the public AppKit SDK.
    case gesture = 29
    /// The Dock-control event that drives Spaces, Mission Control, App Expose, Launchpad and
    /// Show Desktop with fluid progress. AppKit names raw value 30 NSEventTypeMagnify, but the
    /// Dock reads a type-30 event whose subtype is DockSwipe as a dock swipe.
    /// VERIFIED as a value by [MMF]; behaviour ASSUMED to be unchanged on macOS 26 because
    /// [MMF] keeps this path for every macOS below 27.
    case dockControl = 30

    public var cgType: CGEventType { CGEventType(rawValue: rawValue)! }
}

/// Private CGEvent field numbers. Raw values are the CGEventField numbers.
public enum CGSField: UInt32, CaseIterable, Sendable {
    /// kCGSEventTypeField. Same storage that CGEventSetType writes. VERIFIED [MMF] + round trip
    /// in our tests (setting type 29 reads back 29 from field 55).
    case eventType = 55
    /// Set to 33231 on the type-29 companion of a dock swipe. Meaning unknown. ASSUMED [MMF].
    case dockSwipeCompanionMagic = 41
    /// HID event subtype (an IOHIDEventType). VERIFIED [CT] 0x6E + [MMF] 110.
    case gestureHIDType = 110
    /// Magnification amount, Float32 storage (1.0 = double the size). VERIFIED [CT] 0x71 + [MMF] 113.
    case gestureZoomValue = 113
    /// Rotation in degrees, positive = counter-clockwise. VERIFIED [CT] 0x72 + [MMF] 114.
    case gestureRotationValue = 114
    /// Swipe direction, an IOHIDSwipeMask. VERIFIED [CT] 0x73 + [MMF] 115.
    case gestureSwipeValue = 115
    /// Begin/end-gesture "next subtype". VERIFIED [CT] 0x75. Not used by default.
    case gestureNextSubtype = 117
    /// Dock swipe type, encoded as a Float32 whose bit pattern is the small integer type
    /// (1 => 1.4e-45). ASSUMED [MMF] (it writes the denormal constants verbatim).
    case dockSwipeTypeEncodedA = 119
    /// Dock swipe motion: 1 horizontal, 2 vertical, 3 pinch. ASSUMED [MMF]; agrees with the
    /// shape of IOHIDGestureMotion in [HID] (HorizontalX = 1, VerticalY = 2, Scale = 3).
    case dockSwipeMotion = 123
    /// Dock swipe cumulative origin offset (Float32 storage). ASSUMED [MMF].
    case dockSwipeOriginOffset = 124
    /// Exit speed at the end of a dock swipe, X and Y. [MMF] writes lastDelta * 100 to both.
    case dockSwipeExitSpeedX = 129
    case dockSwipeExitSpeedY = 130
    /// IOHIDEventPhaseBits of the gesture. VERIFIED [CT] 0x84 + [MMF] 132.
    case gesturePhase = 132
    /// Phase repeated here for dock swipes ("not sure if necessary"). ASSUMED [MMF].
    case dockSwipePhaseRepeat = 134
    /// Origin offset again, as an Int64 holding the bit pattern of the Float32 value. ASSUMED [MMF].
    case dockSwipeOriginOffsetBits = 135
    /// 1 when the device direction is inverted (natural scrolling). ASSUMED [MMF].
    case dockSwipeInvertedFromDevice = 136
    /// Same encoded type as field 119. ASSUMED [MMF].
    case dockSwipeTypeEncodedB = 139
    /// Dock swipe motion again (same value as 123). ASSUMED [MMF].
    case dockSwipeMotionRepeat = 165

    public var cgField: CGEventField { CGEventField(rawValue: rawValue)! }
}

/// IOHIDEventType values used as the gesture subtype (field 110). All VERIFIED [HID].
public enum HIDEventType: Int64, Sendable {
    case rotation = 5
    case zoom = 8
    case navigationSwipe = 16
    case zoomToggle = 22      // smart magnify; [CT] calls it kTLInfoSubtypeSmartMagnify = 0x16
    case dockSwipe = 23
    /// [CT] begin/end gesture wrappers (0x3D, 0x3E). Not part of IOHIDEventType.
    case beginGesture = 61
    case endGesture = 62
}

/// IOHIDEventPhaseBits. VERIFIED [HID].
public enum HIDPhase: Int64, Sendable {
    case undefined = 0
    case began = 1
    case changed = 2
    case ended = 4
    case cancelled = 8
    case mayBegin = 128
}

/// IOHIDSwipeMask. VERIFIED [HID] (and [CT] kTLInfoSwipe* agree).
/// Back = left, forward = right: VERIFIED [MMF] Actions.m maps its "left" (mouse button 4,
/// back) to kIOHIDSwipeLeft.
public enum HIDSwipe: Int64, Sendable {
    case none = 0
    case up = 1
    case down = 2
    case left = 4
    case right = 8
}

/// Dock swipe motion values for field 123/165, and the matching Float32-bit-pattern encoding
/// for fields 119/139. ASSUMED [MMF].
public enum DockSwipeMotion: Int64, Sendable {
    case horizontal = 1   // Spaces
    case vertical = 2     // Mission Control (negative offset) / App Expose (positive offset)
    case pinch = 3        // Launchpad / Show Desktop

    /// The Float32 whose bits equal the motion number, widened to Double for
    /// CGEventSetDoubleValueField. 1 -> 1.401298464324817e-45.
    public var encoded: Double { Double(Float(bitPattern: UInt32(rawValue))) }
}

/// Magic constant written into field 41 of the type-29 companion. ASSUMED [MMF], meaning unknown.
public let dockSwipeCompanionMagicValue: Int64 = 33231

/// Public scroll fields and values, from [CG] CGEventTypes.h. Listed so every number the
/// synthesizer writes is named in one place.
public enum CGScrollField {
    public static let isContinuous = CGEventField.scrollWheelEventIsContinuous            // 88
    public static let scrollPhase = CGEventField.scrollWheelEventScrollPhase              // 99
    public static let momentumPhase = CGEventField.scrollWheelEventMomentumPhase          // 123
    public static let pointDeltaAxis1 = CGEventField.scrollWheelEventPointDeltaAxis1      // 96
    public static let pointDeltaAxis2 = CGEventField.scrollWheelEventPointDeltaAxis2      // 97
    public static let fixedDeltaAxis1 = CGEventField.scrollWheelEventFixedPtDeltaAxis1    // 93
    public static let fixedDeltaAxis2 = CGEventField.scrollWheelEventFixedPtDeltaAxis2    // 94
}

extension CGEvent {
    func set(_ field: CGSField, _ value: Int64) { setIntegerValueField(field.cgField, value: value) }
    func set(_ field: CGSField, double value: Double) { setDoubleValueField(field.cgField, value: value) }
    public func get(_ field: CGSField) -> Int64 { getIntegerValueField(field.cgField) }
    public func getDouble(_ field: CGSField) -> Double { getDoubleValueField(field.cgField) }
}
