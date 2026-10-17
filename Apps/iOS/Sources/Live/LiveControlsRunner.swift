import Foundation
import GlasspadKit
import Observation
import UIKit

/// Runs the Live Activity's buttons in the app. iOS wakes the app in the background for each
/// press (with the iPhone locked too); the app connects to the Mac if it is not connected,
/// sends the press, then keeps the connection for `LiveLinger.hold` seconds so the next press
/// goes out at once. When iOS suspends the app after that, the next press connects again.
@MainActor
enum LiveControlsRunner {
    enum Command { case playPause, back, forward, nextSlide, previousSlide }

    private static var linger = LiveLinger()
    private static var lingerTask = UIBackgroundTaskIdentifier.invalid
    /// Counts holders, so one left over from before a suspension never ends a newer one.
    private static var holder = 0

    static func run(_ command: Command) async {
        let pressed = Date()
        do {
            try await MacSession.shared.withConnection(timeout: 6) { session in
                // Shown as a tool, Remote tells the Mac itself (the screen underneath does not).
                if AppRouter.shared.showRemote, command != .nextSlide, command != .previousSlide {
                    session.send(.modeSelected(.remote))
                }
                await send(command, session, pressed: pressed)
                keepConnection()
            }
            LiveActivityController.shared.pressWorked()
        } catch {
            LiveActivityController.shared.pressFailed(reason(error))
        }
    }

    private static func send(_ command: Command, _ session: MacSession, pressed: Date) async {
        let store = MediaStore.shared
        switch command {
        case .nextSlide: session.send(.presentNext)
        case .previousSlide: session.send(.presentPrevious)
        case .playPause: store.togglePlay()
        case .back, .forward:
            let action: RemoteAction = command == .back ? .back : .forward
            guard var output = keymap(session).output(action) else { return }
            if case .seek = output {
                // A jump starts from where the film is now: what the phone last heard may be
                // from before it was locked. Ask, and wait up to a second for the answer.
                session.send(.mediaRequest)
                for _ in 0..<10 {
                    if let at = session.mediaReceivedAt, at >= pressed { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard let fresh = keymap(session).output(action) else { return }
                output = fresh
            }
            switch output {
            case .media(.nextTrack): store.next()
            case .media(.previousTrack): store.previous()
            case .media(.playPause): store.togglePlay()
            default:
                let state = store.state
                let canSeek = LiveControls.Remote.canSeek(state: state, keymap: keymap(session))
                let messages = RemoteKeymap.message(for: output, position: store.playback.position(at: Date()),
                                                    canSeek: canSeek, duration: state?.duration)
                for message in messages {
                    if case .mediaControl(.seek(let target)) = message { store.seek(to: target) } else { session.send(message) }
                }
            }
        }
    }

    /// The Remote's controls for what plays now, as the Remote screen picks them.
    private static func keymap(_ session: MacSession) -> RemoteKeymap {
        let state = MediaStore.shared.state
        return RemoteKeymap(frontmost: session.frontmostBundleID, playing: state?.sourceBundleID,
                            nowPlaying: [state?.title, state?.artist, state?.album])
    }

    /// Short enough for one line on the Lock Screen.
    private static func reason(_ error: Error) -> String {
        let name = PairingStore.shared.selected?.name ?? "your Mac"
        switch error as? MacSession.SessionError {
        case .replaced?: return "Another iPhone is using \(name)"
        case .notPaired?: return "Open Glasspad to pair"
        default: return "Could not reach \(name)"
        }
    }

    // MARK: Keeping the connection

    private static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Holds the connection open a little longer after each press. One holder at a time; a
    /// press while it holds only moves the end later.
    private static func keepConnection() {
        guard linger.pressed(at: uptime) else { return }
        endBackgroundTask()
        holder += 1
        let mine = holder
        lingerTask = UIApplication.shared.beginBackgroundTask(withName: "Glasspad Lock Screen controls") {
            // iOS is about to suspend the app: let go now.
            MainActor.assumeIsolated { stopHolding(mine) }
        }
        Task { @MainActor in
            try? await MacSession.shared.withConnection(timeout: 1) { _ in
                while mine == holder, linger.isHolding(at: uptime) {
                    try? await Task.sleep(for: .seconds(linger.remaining(at: uptime)))
                }
            }
            stopHolding(mine)
        }
    }

    private static func stopHolding(_ which: Int) {
        guard which == holder else { return }
        linger.stop()
        endBackgroundTask()
    }

    private static func endBackgroundTask() {
        guard lingerTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(lingerTask)
        lingerTask = .invalid
    }
}

/// The Present timer as the Live Activity needs it. Present's screen reports its timer here
/// whenever it starts, pauses or resets; the state only changes then, never while it counts.
@MainActor
@Observable
final class LivePresentTimer {
    static let shared = LivePresentTimer()

    private(set) var state = LiveControls.Present(countingFrom: nil, elapsed: 0)

    private init() {}

    func report(isRunning: Bool, elapsed: TimeInterval, length: TimeInterval? = nil) {
        state = LiveControls.Present(isRunning: isRunning, elapsed: elapsed, length: length, now: Date())
    }
}
