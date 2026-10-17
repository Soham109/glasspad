import AppIntents

// The Live Activity's buttons. iOS runs them in the app's own process (waking it in the
// background when it is suspended, even with the iPhone locked), never in the widget
// extension, so the press goes out over the app's connection to the Mac (`LiveControlsRunner`).
// Compiled into both targets because the widget names them in its buttons. Hidden from the
// Shortcuts app: Siri has its own actions for these.

struct LivePlayPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !GLASSPAD_WIDGET
        await LiveControlsRunner.run(.playPause)
        #endif
        return .result()
    }
}

struct LiveSkipBackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Back"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !GLASSPAD_WIDGET
        await LiveControlsRunner.run(.back)
        #endif
        return .result()
    }
}

struct LiveSkipForwardIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Forward"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !GLASSPAD_WIDGET
        await LiveControlsRunner.run(.forward)
        #endif
        return .result()
    }
}

struct LiveNextSlideIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next Slide"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !GLASSPAD_WIDGET
        await LiveControlsRunner.run(.nextSlide)
        #endif
        return .result()
    }
}

struct LivePreviousSlideIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Previous Slide"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !GLASSPAD_WIDGET
        await LiveControlsRunner.run(.previousSlide)
        #endif
        return .result()
    }
}
