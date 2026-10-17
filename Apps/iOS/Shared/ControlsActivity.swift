import ActivityKit
import Foundation
import GlasspadKit

/// The Live Activity shown while Remote, Media or Present is in use: real controls on the
/// Lock Screen and in the Dynamic Island. Shared by the app (which starts, updates and ends
/// it, and runs its buttons) and the widget extension (which draws it).
struct ControlsActivityAttributes: ActivityAttributes {
    typealias ContentState = LiveControls
}

/// Deep links the app understands. Widgets use `trackpad`.
enum GlasspadLink {
    static let trackpad = URL(string: "glasspad://trackpad")!
}
