import CryptoKit
import Foundation
import GlasspadKit
import ImageIO
import UniformTypeIdentifiers

/// What one source (the MediaRemote helper or a player's AppleScript) says is playing.
public struct NowPlayingSnapshot: Equatable, Sendable {
    public enum Provider: String, Sendable {
        /// MediaRemote through the perl helper: any player.
        case mediaRemote
        /// Apple Events to Spotify.
        case spotify
        /// Apple Events to Music.
        case music
    }

    public var provider: Provider
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    /// Position at `elapsedAt`.
    public var elapsed: TimeInterval?
    public var elapsedAt: Date?
    public var playbackRate: Double?
    public var isPlaying: Bool
    /// The process that plays (for a browser tab this can be a WebKit helper).
    public var bundleID: String?
    /// The app that owns `bundleID`, when MediaRemote reports one (browsers, web views).
    public var parentBundleID: String?
    public var appName: String?
    public var artworkData: Data?
    /// Spotify gives a URL to full-size cover art instead of data.
    public var artworkURL: URL?
    public var shuffle: Bool?
    public var repeatMode: MediaRepeatMode?
    public var trackID: String?

    public init(provider: Provider, title: String, artist: String? = nil, album: String? = nil,
                duration: TimeInterval? = nil, elapsed: TimeInterval? = nil, elapsedAt: Date? = nil,
                playbackRate: Double? = nil, isPlaying: Bool, bundleID: String? = nil, parentBundleID: String? = nil,
                appName: String? = nil, artworkData: Data? = nil, artworkURL: URL? = nil, shuffle: Bool? = nil,
                repeatMode: MediaRepeatMode? = nil, trackID: String? = nil) {
        self.provider = provider
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.elapsedAt = elapsedAt
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.bundleID = bundleID
        self.parentBundleID = parentBundleID
        self.appName = appName
        self.artworkData = artworkData
        self.artworkURL = artworkURL
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.trackID = trackID
    }

    /// The app to show as the source: the parent app for browser tabs.
    public var sourceBundleID: String? { parentBundleID ?? bundleID }

    /// Same song, whichever source reported it.
    public var trackKey: String {
        [title, artist ?? "", album ?? ""].map { $0.lowercased() }.joined(separator: "\u{1F}")
    }

    /// Position now: the reported one, advanced by the playback rate while playing.
    public func elapsed(at now: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        var value = elapsed
        if isPlaying, let at = elapsedAt {
            value += max(0, now.timeIntervalSince(at)) * (playbackRate ?? 1)
        }
        if let duration, duration > 0 { value = min(value, duration) }
        return max(0, value)
    }
}

/// Combines the sources into one picture of what plays.
public enum NowPlayingMerger {
    /// The adapter (MediaRemote) wins when it has something: it covers every player and streams
    /// changes. An AppleScript snapshot fills the gaps (artwork, shuffle, repeat) for the same
    /// song, and stands in when the adapter has nothing.
    public static func merge(adapter: NowPlayingSnapshot?, script: NowPlayingSnapshot?) -> NowPlayingSnapshot? {
        guard var base = adapter else { return script }
        guard let script, script.trackKey == base.trackKey || script.sourceBundleID == base.sourceBundleID
        else { return base }
        let sameTrack = script.trackKey == base.trackKey
        if sameTrack {
            if base.artworkData == nil { base.artworkURL = base.artworkURL ?? script.artworkURL }
            if base.artworkData == nil, base.artworkURL == nil { base.artworkData = script.artworkData }
            base.duration = base.duration ?? script.duration
            if base.elapsed == nil {
                base.elapsed = script.elapsed
                base.elapsedAt = script.elapsedAt
            }
        }
        base.shuffle = base.shuffle ?? script.shuffle
        base.repeatMode = base.repeatMode ?? script.repeatMode
        base.appName = base.appName ?? script.appName
        return base
    }
}

/// Turns snapshots into the `MediaState` the phone gets. Artwork and app icons go over the link
/// once per session; later states carry only their ids. The position is always the true one at
/// build time, and a state whose only change is the position moving as the phone predicts is
/// not built at all (`build` returns nil), so nothing is resent each second just because time
/// passed.
struct MediaWireBuilder {
    private(set) var sentArtworkIDs: Set<String> = []
    private(set) var sentIconIDs: Set<String> = []
    private var last: (key: MediaState, elapsed: TimeInterval?, at: Date)?

    /// The phone asked for everything again (it opened Media mode or reconnected).
    mutating func reset() {
        sentArtworkIDs = []
        sentIconIDs = []
        last = nil
    }

    struct Inputs {
        var snapshot: NowPlayingSnapshot?
        var now: Date
        var volume: Double?
        var brightness: Double?
        var outputs: [MediaOutput]?
        var notice: MediaNotice?
        /// Ready-to-send artwork for the snapshot's song.
        var artwork: (id: String, data: Data)?
        var sourceName: String?
        var sourceIconPNG: Data?
        var canSeek: Bool?
    }

    /// The state to send, or nil when the phone's own prediction already matches it.
    mutating func build(_ input: Inputs) -> MediaState? {
        var state = MediaState(volume: input.volume, brightness: input.brightness)
        state.outputs = input.outputs
        state.notice = input.notice
        if let s = input.snapshot {
            state.title = s.title
            state.artist = s.artist.flatMap { $0.isEmpty ? nil : $0 }
            state.album = s.album.flatMap { $0.isEmpty ? nil : $0 }
            state.isPlaying = s.isPlaying
            state.playbackRate = s.isPlaying ? (s.playbackRate.map { $0 > 0 ? $0 : 1 } ?? 1) : 0
            state.duration = s.duration.flatMap { $0 > 0 ? $0 : nil }
            state.elapsed = s.elapsed(at: input.now)
            state.shuffle = s.shuffle
            state.repeatMode = s.repeatMode
            state.canSeek = input.canSeek
            state.sourceBundleID = s.sourceBundleID
            state.sourceName = input.sourceName ?? s.appName
            state.artworkID = input.artwork?.id
        }
        // Everything but the position and the one-time payloads.
        var key = state
        key.elapsed = nil
        if let last, last.key == key, positionAsPredicted(state.elapsed, last: last, rate: state.playbackRate ?? 0, now: input.now) {
            return nil
        }
        last = (key, state.elapsed, input.now)
        if let id = state.sourceBundleID, let icon = input.sourceIconPNG, !sentIconIDs.contains(id) {
            state.sourceIconPNG = icon
            sentIconIDs.insert(id)
        }
        if let art = input.artwork, !sentArtworkIDs.contains(art.id) {
            state.artworkPNG = art.data
            sentArtworkIDs.insert(art.id)
        }
        return state
    }

    private func positionAsPredicted(_ elapsed: TimeInterval?, last: (key: MediaState, elapsed: TimeInterval?, at: Date),
                                     rate: Double, now: Date) -> Bool {
        switch (elapsed, last.elapsed) {
        case (nil, nil): return true
        case let (actual?, previous?):
            let predicted = previous + now.timeIntervalSince(last.at) * rate
            if let d = last.key.duration, predicted > d { return abs(actual - d) < 1 }
            return abs(predicted - actual) < 1
        default: return false
        }
    }
}

/// Artwork bytes ready for the phone: JPEG or PNG, at most `maxPixels` on the long side.
enum ArtworkEncoder {
    static let maxPixels = 1200
    static let maxBytes = 1_500_000

    /// A stable id for the image (same bytes, same id, across launches).
    static func id(for data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// The image as is when it is a modest JPEG or PNG; otherwise a JPEG thumbnail.
    static func prepare(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let type = CGImageSourceGetType(source) as String?
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let friendly = type == UTType.jpeg.identifier || type == UTType.png.identifier
        if friendly, data.count <= maxBytes, max(width, height) <= maxPixels { return data }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
