import ActivityKit
import Foundation
import GlasspadKit
import Observation
import UIKit

/// Shows Remote's or Present's buttons on the Lock Screen and in the Dynamic Island while one
/// of them (or Media) is on screen. iOS only lets an app start a Live Activity while it is in
/// front, so it starts when the screen opens and ends when another mode replaces it. In the
/// background it is only updated, and only when what it shows changes: the app sends nothing
/// while it sits still, and the Present timer counts by itself.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<ControlsActivityAttributes>?
    /// What the activity shows now, to skip updates that change nothing.
    private var shown: LiveControls?
    /// Glasspad is in front (or only covered by Control Center): activities can start and end.
    private var foreground = false
    /// The person swiped the activity away: it stays away until that screen is left.
    private var dismissed: LiveControls.Kind?
    /// Why the last press did not reach the Mac.
    private var problem: String?

    private init() {
        // iOS may have ended the app in the background and now launched it again for a press:
        // the activity on the Lock Screen is still this one, so keep it.
        let existing = Activity<ControlsActivityAttributes>.activities
        if let first = existing.first {
            adopt(first)
            shown = first.content.state
        }
        for extra in existing.dropFirst() { end(extra) }
        LegacyTrackpadActivity.endAll()
        watch()
    }

    /// `active` is false only once the app is in the background.
    func sceneChanged(active: Bool) {
        foreground = active
        // Back in the app, which shows the connection itself: the last press's trouble is old news.
        if active { problem = nil }
        refresh()
    }

    /// Called whenever the screen, the link or what plays may have changed. Cheap: it only
    /// sends an update when the state differs from what is shown.
    func refresh() {
        guard let wanted = wantedControls() else {
            // Out of use. In the background nothing on screen changes, so keep what is there.
            if foreground {
                dismissed = nil
                if let activity { end(activity) }
                activity = nil
                shown = nil
                problem = nil
            }
            return
        }
        if let dismissed, dismissed != wanted.kind { self.dismissed = nil }
        if let activity {
            // Launched again in the background for a press, the app may think another screen
            // was open: never turn Present's controls into Remote's (or back) from there.
            if !foreground, let shown, shown.kind != wanted.kind { return }
            update(activity, wanted)
        } else if foreground, dismissed == nil {
            start(wanted)
        }
    }

    /// A Lock Screen press reached the Mac.
    func pressWorked() {
        guard problem != nil else { return }
        problem = nil
        refresh()
    }

    /// A Lock Screen press could not reach the Mac: say so on the activity.
    func pressFailed(_ reason: String) {
        problem = reason
        refresh()
    }

    // MARK: What to show

    /// Remote's controls while Remote or Media shows, Present's while Present does.
    private func wantedControls() -> LiveControls? {
        guard PhoneSettings.shared.hasOnboarded, let mac = PairingStore.shared.selected else { return nil }
        let router = AppRouter.shared
        let modes = router.screenModes
        if router.showPresenter || modes.contains(.present) {
            return .present(LivePresentTimer.shared.state, macName: mac.name, problem: problem)
        }
        if router.showRemote || modes.contains(.remote) || modes.contains(.media) {
            let store = MediaStore.shared
            let remote = LiveControls.Remote(state: store.state, isPlaying: store.playback.isPlaying(at: Date()),
                                             frontmost: MacSession.shared.frontmostBundleID)
            return .remote(remote, macName: mac.name, problem: problem)
        }
        return nil
    }

    /// Re-runs `refresh` whenever anything `wantedControls` reads changes.
    private func watch() {
        withObservationTracking {
            _ = wantedControls()
        } onChange: {
            Task { @MainActor in
                LiveActivityController.shared.refresh()
                LiveActivityController.shared.watch()
            }
        }
    }

    // MARK: ActivityKit

    private func start(_ content: LiveControls) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let new = try Activity.request(attributes: ControlsActivityAttributes(),
                                           content: Self.content(content), pushType: nil)
            adopt(new)
            shown = content
        } catch {
            GPLog.log("Live Activity did not start: \(error)")
            activity = nil
            shown = nil
        }
    }

    private func adopt(_ new: Activity<ControlsActivityAttributes>) {
        activity = new
        let ref = ActivityRef(activity: new)
        let id = new.id
        Task {
            for await state in ref.activity.activityStateUpdates where state == .dismissed || state == .ended {
                LiveActivityController.shared.activityGone(id, dismissed: state == .dismissed)
            }
        }
    }

    private func activityGone(_ id: String, dismissed byPerson: Bool) {
        guard activity?.id == id else { return }
        if byPerson { dismissed = shown?.kind }
        activity = nil
        shown = nil
    }

    private func update(_ activity: Activity<ControlsActivityAttributes>, _ content: LiveControls) {
        guard content != shown else { return }
        shown = content
        let ref = ActivityRef(activity: activity)
        Task { await ref.activity.update(Self.content(content)) }
    }

    private func end(_ old: Activity<ControlsActivityAttributes>) {
        let ref = ActivityRef(activity: old)
        Task { await ref.activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// A talk with a length goes stale when it reaches zero, so the clock can show the time over.
    private static func content(_ state: LiveControls) -> ActivityContent<LiveControls> {
        ActivityContent(state: state, staleDate: state.present?.endsAt)
    }
}

/// ActivityKit's `Activity` is safe to use from any thread but is not marked `Sendable`.
private struct ActivityRef<A: ActivityAttributes>: @unchecked Sendable {
    let activity: Activity<A>
}

/// The connection activity earlier builds started on the trackpad ("Connected", "Paused"),
/// under its original name so ActivityKit finds it. Kept only so an update can end one left
/// on the Lock Screen.
private struct TrackpadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var status: String
        var macName: String
    }
}

private enum LegacyTrackpadActivity {
    @MainActor
    static func endAll() {
        for old in Activity<TrackpadActivityAttributes>.activities {
            let ref = ActivityRef(activity: old)
            Task { await ref.activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
