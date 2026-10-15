import Foundation

/// The phone's view of playback: the Mac's last `MediaState` plus the user's taps not yet
/// confirmed. A tap shows at once (optimistic); the Mac's next state that agrees confirms it,
/// and if none agrees within `confirmWindow` the Mac's state wins again.
///
/// Position ticks locally from an anchor (position, time, rate), so the progress bar moves
/// smoothly between the Mac's updates and stops the moment pause is tapped.
public struct MediaPlayback: Equatable, Sendable {
    /// The Mac's latest state, as received.
    public private(set) var mac: MediaState?
    /// How long a tap waits for the Mac to agree.
    public var confirmWindow: TimeInterval = 2.5

    /// Position as the Mac last reported it.
    private var macAnchor: Anchor?
    /// Position after a play/pause or seek tap, used until the Mac agrees or the tap expires.
    private var tapAnchor: Anchor?
    private var pendingPlaying: Pending<Bool>?
    private var pendingSeek: Pending<TimeInterval>?
    private var pendingShuffle: Pending<Bool>?
    private var pendingRepeat: Pending<MediaRepeatMode>?
    private var pendingOutput: Pending<String>?

    struct Anchor: Equatable, Sendable {
        var position: TimeInterval
        var at: Date
        var rate: Double
    }

    struct Pending<Value: Equatable & Sendable>: Equatable, Sendable {
        var value: Value
        var at: Date
    }

    public init() {}

    // MARK: Reading

    /// Something is loaded on the Mac.
    public var hasTrack: Bool { (mac?.title ?? "").isEmpty == false }

    public func isPlaying(at now: Date) -> Bool {
        if let p = live(pendingPlaying, now) { return p.value }
        return mac?.isPlaying ?? false
    }

    public func shuffle(at now: Date) -> Bool? { live(pendingShuffle, now)?.value ?? mac?.shuffle }

    public func repeatMode(at now: Date) -> MediaRepeatMode? { live(pendingRepeat, now)?.value ?? mac?.repeatMode }

    /// Outputs with the one just picked marked current.
    public func outputs(at now: Date) -> [MediaOutput] {
        guard var list = mac?.outputs else { return [] }
        if let picked = live(pendingOutput, now)?.value, list.contains(where: { $0.id == picked }) {
            for i in list.indices { list[i].isCurrent = list[i].id == picked }
        }
        return list
    }

    /// Position now, nil when the Mac does not report one.
    public func position(at now: Date) -> TimeInterval? {
        let tapLive = live(pendingPlaying, now) != nil || live(pendingSeek, now) != nil
        guard let anchor = (tapLive ? tapAnchor : nil) ?? macAnchor else { return nil }
        var value = anchor.position + max(0, now.timeIntervalSince(anchor.at)) * anchor.rate
        if let d = mac?.duration, d > 0 { value = min(value, d) }
        return max(0, value)
    }

    // MARK: The Mac

    /// A state from the Mac arrived at `now`.
    public mutating func receive(_ state: MediaState, at now: Date) {
        let trackChanged = state.title != mac?.title || state.artist != mac?.artist || state.album != mac?.album
        mac = state
        if trackChanged {
            pendingPlaying = nil
            pendingSeek = nil
        }
        if let p = pendingPlaying, p.value == state.isPlaying || expired(p, now) { pendingPlaying = nil }
        if let p = pendingShuffle, p.value == state.shuffle || expired(p, now) { pendingShuffle = nil }
        if let p = pendingRepeat, p.value == state.repeatMode || expired(p, now) { pendingRepeat = nil }
        if let p = pendingOutput, state.outputs?.first(where: \.isCurrent)?.id == p.value || expired(p, now) {
            pendingOutput = nil
        }
        if let p = pendingSeek, expired(p, now) || state.elapsed.map({ abs($0 - p.value) < 2.5 }) == true {
            pendingSeek = nil
        }
        if let e = state.elapsed {
            macAnchor = Anchor(position: e, at: now, rate: state.isPlaying ? (state.playbackRate.map { $0 > 0 ? $0 : 1 } ?? 1) : 0)
        } else {
            macAnchor = nil
        }
        if pendingPlaying == nil, pendingSeek == nil { tapAnchor = nil }
    }

    /// The link dropped or the Mac changed: forget everything.
    public mutating func reset() { self = MediaPlayback() }

    // MARK: Taps

    /// Play/pause tapped: returns the command to send.
    public mutating func togglePlay(at now: Date) -> MediaCommand {
        let playing = !isPlaying(at: now)
        let pos = position(at: now)
        pendingPlaying = Pending(value: playing, at: now)
        if let pos {
            tapAnchor = Anchor(position: pos, at: now, rate: playing ? max(1, mac?.playbackRate ?? 1) : 0)
        }
        return .playPause
    }

    /// Next or previous: the new song starts from zero.
    public mutating func skipped(at now: Date) {
        if macAnchor != nil {
            pendingSeek = Pending(value: 0, at: now)
            tapAnchor = Anchor(position: 0, at: now, rate: isPlaying(at: now) ? 1 : 0)
        }
    }

    /// Scrubbed to `position`; returns the control to send.
    public mutating func seek(to position: TimeInterval, at now: Date) -> MediaControl {
        let target = max(0, min(position, mac?.duration ?? position))
        let playing = isPlaying(at: now)
        pendingSeek = Pending(value: target, at: now)
        tapAnchor = Anchor(position: target, at: now, rate: playing ? max(1, mac?.playbackRate ?? 1) : 0)
        return .seek(target)
    }

    public mutating func toggleShuffle(at now: Date) -> MediaControl {
        let on = !(shuffle(at: now) ?? false)
        pendingShuffle = Pending(value: on, at: now)
        return .setShuffle(on)
    }

    public mutating func cycleRepeat(at now: Date) -> MediaControl {
        let next = (repeatMode(at: now) ?? .off).next
        pendingRepeat = Pending(value: next, at: now)
        return .setRepeat(next)
    }

    public mutating func selectOutput(_ id: String, at now: Date) -> MediaControl {
        pendingOutput = Pending(value: id, at: now)
        return .selectOutput(id: id)
    }

    // MARK: Helpers

    private func expired<V>(_ p: Pending<V>, _ now: Date) -> Bool { now.timeIntervalSince(p.at) > confirmWindow }

    private func live<V>(_ p: Pending<V>?, _ now: Date) -> Pending<V>? {
        guard let p, !expired(p, now) else { return nil }
        return p
    }
}
