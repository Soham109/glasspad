import Foundation

public enum MouseButton: String, Codable, Sendable { case left, right, middle }

/// Phase of a continuous gesture (magnify, rotate, swipe).
public enum GesturePhase: String, Codable, Sendable { case began, changed, ended, cancelled }

/// Finger-driven scroll phase. `none` is used on momentum events (macOS sets scroll phase 0 there).
public enum ScrollPhase: String, Codable, Sendable { case none, began, changed, ended, cancelled }

/// Momentum phase after the fingers lift. `none` while fingers are down.
public enum MomentumPhase: String, Codable, Sendable { case none, began, changed, ended }

/// Dock-level swipe gestures that follow the fingers.
public enum SwipeKind: String, Codable, Sendable {
    case spaces, missionControl, appExpose, launchpad, showDesktop
}

/// A stream of finger-driven motion that may safely be carried on through a short Wi-Fi gap
/// (`GestureRecognizer.continuingMotion`): the Mac's output scheduler extrapolates only these.
public enum MotionStream: Sendable, Equatable { case move, drag, scroll }

/// Output of `GestureRecognizer`, consumed by the Mac synth.
public enum GestureEvent: Equatable, Sendable {
    /// Pointer move in Mac points (+x right, +y down), already accelerated.
    case move(dx: Double, dy: Double)
    /// Button transition. `clickCount` is 1, 2 or 3 (double and triple click).
    case button(MouseButton, down: Bool, clickCount: Int)
    /// Pointer move while the left button is held, Mac points, accelerated.
    case drag(dx: Double, dy: Double)
    /// Pixel scroll in CGEvent convention: positive dy = wheel up (content moves down),
    /// positive dx = content moves right. Natural scrolling is already applied.
    case scroll(dx: Double, dy: Double, phase: ScrollPhase, momentum: MomentumPhase)
    /// Relative scale change for this step (0.1 = 10% bigger).
    case magnify(delta: Double, phase: GesturePhase)
    /// Rotation for this step in degrees, positive = counterclockwise.
    case rotate(degrees: Double, phase: GesturePhase)
    /// Two-finger double tap.
    case smartMagnify
    /// Fluid Dock swipe. `progress` is cumulative since `began`: 1.0 = one full transition.
    /// spaces: positive = fingers moved left (go to the Space on the right);
    /// missionControl: positive = up; appExpose: positive = down;
    /// launchpad: positive = fingers pinched in; showDesktop: positive = fingers spread out.
    case swipe(SwipeKind, progress: Double, phase: GesturePhase)
    /// Swipe between pages. `back` = fingers moved right.
    case navigate(back: Bool)
    /// Press-and-hold force click: 1 = start (left button goes down just before), 2 = deep press.
    /// When settings.lookUp == .forceClick, stage 2 is the Look Up trigger; the synth picks native or fallback.
    case forceClick(stage: Int)
    /// Three-finger tap Look Up (only when settings.lookUp == .threeFingerTap).
    case lookUp
    /// Two-finger swipe left from the right edge.
    case notificationCenter
}
