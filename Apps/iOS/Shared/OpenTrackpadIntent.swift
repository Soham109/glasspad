import AppIntents

/// Opens Glasspad on the trackpad. Used by the Control Center control and by Siri.
/// Compiled into the app and the widget extension, as iOS requires for controls that open
/// the app; the system runs it in the app.
struct OpenTrackpadIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Trackpad"
    static let description = IntentDescription("Opens Glasspad on the trackpad screen.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !GLASSPAD_WIDGET
        AppRouter.shared.show(.trackpad)
        #endif
        return .result()
    }
}
