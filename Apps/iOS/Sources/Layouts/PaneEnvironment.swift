import SwiftUI

extension EnvironmentValues {
    /// Room a mode keeps clear above its content for the mode pill. nil on a full screen (each
    /// mode keeps its own room); a layout pane that is not under the pill sets a small value,
    /// so its content starts near the top of the pane.
    @Entry var modeTopClearance: CGFloat? = nil
    /// The mode is one pane of a layout, and may have much less room than the whole screen.
    @Entry var inLayoutPane = false
}
