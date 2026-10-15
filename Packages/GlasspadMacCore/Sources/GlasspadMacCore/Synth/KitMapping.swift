import CoreGraphics
import GlasspadKit

// Translations from GlasspadKit's gesture vocabulary to CoreGraphics values. Kept in one file so
// a change in the kit's enums only touches this file.

extension GesturePhase {
    var hidPhase: HIDPhase {
        switch self {
        case .began: .began
        case .changed: .changed
        case .ended: .ended
        case .cancelled: .cancelled
        }
    }
    var isTerminal: Bool { self == .ended || self == .cancelled }
}

extension ScrollPhase {
    /// CGScrollPhase raw values ([CG]): began 1, changed 2, ended 4, cancelled 8 (mayBegin 128 unused).
    var cgValue: Int64 {
        switch self {
        case .none: 0
        case .began: 1
        case .changed: 2
        case .ended: 4
        case .cancelled: 8
        }
    }
}

extension MomentumPhase {
    /// CGMomentumScrollPhase raw values ([CG]): none 0, begin 1, continuous 2, end 3.
    var cgValue: Int64 {
        switch self {
        case .none: 0
        case .began: 1
        case .changed: 2
        case .ended: 3
        }
    }
}

extension SwipeKind {
    var synthGesture: SynthGesture {
        switch self {
        case .spaces: .spaces
        case .missionControl: .missionControl
        case .appExpose: .appExpose
        case .launchpad: .launchpad
        case .showDesktop: .showDesktop
        }
    }
}
