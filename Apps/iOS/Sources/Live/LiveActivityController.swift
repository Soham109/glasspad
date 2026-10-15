import ActivityKit
import Foundation
import GlasspadKit
import UIKit

/// Starts a Live Activity when the trackpad is in use, keeps its connection state current,
/// marks it paused when Glasspad leaves the screen (iOS suspends the connection then), and
/// ends it when the trackpad is closed for another mode or the Mac is forgotten.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<TrackpadActivityAttributes>?
    private var lastState: TrackpadActivityAttributes.ContentState?
    private var sceneActive = false

    private init() {
        // Activities left over from an earlier run describe a connection that no longer exists.
        for old in Activity<TrackpadActivityAttributes>.activities {
            let ref = ActivityRef(activity: old)
            Task { await ref.activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func sceneChanged(active: Bool) {
        sceneActive = active
        if active {
            refresh()
        } else if activity != nil {
            // Leaving the app: say so while we still can run.
            let app = UIApplication.shared
            let task = app.beginBackgroundTask(withName: "Pause Live Activity", expirationHandler: nil)
            let paused = currentContent(status: .paused)
            Task {
                await self.push(paused)
                app.endBackgroundTask(task)
            }
        }
    }

    /// Called whenever the link state or the mode changes.
    func refresh() {
        guard sceneActive else { return }
        let router = AppRouter.shared
        guard router.mode == .trackpad, PhoneSettings.shared.hasOnboarded,
              PairingStore.shared.selected != nil else {
            end()
            return
        }
        let content = currentContent(status: Self.status(MacSession.shared.state))
        if activity == nil {
            start(content)
        } else {
            Task { await push(content) }
        }
    }

    private func start(_ content: TrackpadActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: TrackpadActivityAttributes(),
                                            content: ActivityContent(state: content, staleDate: nil),
                                            pushType: nil)
            lastState = content
        } catch {
            activity = nil
        }
    }

    private func push(_ content: TrackpadActivityAttributes.ContentState) async {
        guard let activity, content != lastState else { return }
        lastState = content
        let ref = ActivityRef(activity: activity)
        // A paused activity goes stale after a while, so the system can show it as out of date.
        let stale = content.status == .paused ? Date().addingTimeInterval(15 * 60) : nil
        await ref.activity.update(ActivityContent(state: content, staleDate: stale))
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        let ref = ActivityRef(activity: activity)
        Task { await ref.activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func currentContent(status: TrackpadActivityAttributes.ContentState.Status) -> TrackpadActivityAttributes.ContentState {
        .init(status: status, macName: PairingStore.shared.selected?.name ?? "your Mac")
    }

    private static func status(_ state: LinkState) -> TrackpadActivityAttributes.ContentState.Status {
        switch state {
        case .connected: .connected
        case .searching, .connecting: .connecting
        case .idle, .failed: .offline
        }
    }
}

/// ActivityKit's `Activity` is safe to use from any thread but is not marked `Sendable`.
private struct ActivityRef: @unchecked Sendable {
    let activity: Activity<TrackpadActivityAttributes>
}
