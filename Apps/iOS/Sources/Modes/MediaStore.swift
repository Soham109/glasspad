import Foundation
import GlasspadKit
import SwiftUI
import UIKit

/// The phone side of Media mode: the Mac's states merged with the user's taps
/// (`MediaPlayback`), plus artwork and app icons cached by id, since the Mac sends each only
/// once per session.
@MainActor
@Observable
final class MediaStore {
    static let shared = MediaStore()

    private(set) var playback = MediaPlayback()
    /// Artwork of the song now playing, decoded and ready to draw.
    private(set) var artwork: UIImage?
    private(set) var artworkID: String?
    /// Icon of the app now playing.
    private(set) var sourceIcon: UIImage?

    @ObservationIgnored private var artworkCache: [String: UIImage] = [:]
    @ObservationIgnored private var artworkOrder: [String] = []
    @ObservationIgnored private var iconCache: [String: UIImage] = [:]
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private let diskFolder: URL? = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("MediaArtwork", isDirectory: true)
    @ObservationIgnored private var isDemo = false

    var state: MediaState? { playback.mac }

    // MARK: From the Mac

    func receive(_ state: MediaState) {
        #if DEBUG
        if isDemo { return }
        #endif
        playback.receive(state, at: Date())
        absorbImages(state)
    }

    func reset() {
        #if DEBUG
        if isDemo { return }
        #endif
        playback.reset()
        artwork = nil
        artworkID = nil
        sourceIcon = nil
    }

    private func absorbImages(_ state: MediaState) {
        if let id = state.sourceBundleID {
            if let png = state.sourceIconPNG, let image = UIImage(data: png) { iconCache[id] = image }
            let icon = iconCache[id]
            if icon !== sourceIcon { sourceIcon = icon }
        } else if sourceIcon != nil {
            sourceIcon = nil
        }
        guard let id = state.artworkID else {
            if artworkID != nil {
                artworkID = nil
                artwork = nil
            }
            return
        }
        if let data = state.artworkPNG {
            storeArtwork(data, id: id)
        }
        guard id != artworkID || artwork == nil else { return }
        artworkID = id
        if let cached = artworkCache[id] {
            artwork = cached
        } else if let data = readDisk(id) {
            decode(data, id: id)
        } else {
            artwork = nil
        }
    }

    private func storeArtwork(_ data: Data, id: String) {
        writeDisk(data, id: id)
        decode(data, id: id)
    }

    /// Decodes off the main thread so a large cover never stalls a frame.
    private func decode(_ data: Data, id: String) {
        Task {
            guard let image = await UIImage(data: data)?.byPreparingForDisplay() else { return }
            self.remember(image, id: id)
            if self.artworkID == id { self.artwork = image }
        }
    }

    private func remember(_ image: UIImage, id: String) {
        artworkCache[id] = image
        artworkOrder.removeAll { $0 == id }
        artworkOrder.append(id)
        while artworkOrder.count > 12 { artworkCache[artworkOrder.removeFirst()] = nil }
    }

    // Disk cache: artwork survives reconnects and relaunches. Ids are hex digests from the Mac.

    private func file(_ id: String) -> URL? {
        let safe = id.filter { $0.isLetter || $0.isNumber }
        guard !safe.isEmpty else { return nil }
        return diskFolder?.appendingPathComponent(safe)
    }

    private func readDisk(_ id: String) -> Data? {
        file(id).flatMap { try? Data(contentsOf: $0) }
    }

    private func writeDisk(_ data: Data, id: String) {
        guard let url = file(id), let folder = diskFolder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        pruneDisk(folder)
    }

    private func pruneDisk(_ folder: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys),
              files.count > 40 else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - 40) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Taps

    func togglePlay() {
        send(.mediaCommand(playback.togglePlay(at: Date())))
    }

    func next() {
        playback.skipped(at: Date())
        send(.mediaCommand(.nextTrack))
    }

    func previous() {
        // Like any player: back to the start first, the previous song when already near it.
        if (playback.position(at: Date()) ?? 0) > 3 { playback.skipped(at: Date()) }
        send(.mediaCommand(.previousTrack))
    }

    func seek(to position: TimeInterval) {
        send(.mediaControl(playback.seek(to: position, at: Date())))
    }

    func toggleShuffle() { send(.mediaControl(playback.toggleShuffle(at: Date()))) }

    func cycleRepeat() { send(.mediaControl(playback.cycleRepeat(at: Date()))) }

    func selectOutput(_ id: String) { send(.mediaControl(playback.selectOutput(id, at: Date()))) }

    private func send(_ message: ModeMessage) {
        MacSession.shared.send(message)
        scheduleExpiryRefresh()
        #if DEBUG
        if isDemo {
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                self.demoEcho()
            }
        }
        #endif
    }

    /// When a tap goes unconfirmed, redraw once its window ends so the Mac's state shows again.
    private func scheduleExpiryRefresh() {
        expiryTask?.cancel()
        let wait = playback.confirmWindow + 0.05
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            let current = self.playback
            self.playback = current
        }
    }

    // MARK: Demo

    #if DEBUG
    /// Debug builds only (`-GPMediaDemo [title|empty|denied]`): a fake now-playing feed for
    /// simulator screenshots. Taps change the fake state as a Mac would.
    func applyDemo(_ kind: String?) {
        isDemo = true
        let outputs = [
            MediaOutput(id: "builtin", name: "MacBook Pro Speakers", kind: "builtIn", isCurrent: true),
            MediaOutput(id: "pods", name: "Soham's AirPods Pro", kind: "bluetooth", isCurrent: false),
            MediaOutput(id: "tv", name: "Living Room", kind: "airPlay", isCurrent: false),
            MediaOutput(id: "display", name: "Studio Display", kind: "displayPort", isCurrent: false),
        ]
        var state = MediaState(volume: 0.62, brightness: 0.8, outputs: outputs)
        switch kind {
        case "empty":
            break
        case "denied":
            state.notice = MediaNotice(kind: MediaNotice.automationDenied,
                                       message: "To show what Spotify is playing, allow Glasspad to control Spotify in System Settings > Privacy & Security > Automation on your Mac.",
                                       app: "Spotify")
        default:
            state.title = "Everything In Its Right Place (Live at the Astoria, 1995 Remaster)"
            state.artist = "Radiohead"
            state.album = "Kid A Mnesia"
            state.isPlaying = true
            state.playbackRate = 1
            state.duration = 251
            state.elapsed = 74
            state.shuffle = false
            state.repeatMode = .all
            state.canSeek = true
            state.sourceBundleID = "com.spotify.client"
            state.sourceName = "Spotify"
            state.artworkID = "demo"
            artwork = Self.demoArtwork()
            artworkID = "demo"
            sourceIcon = Self.demoIcon()
        }
        playback.receive(state, at: Date())
    }

    /// Flat colour blocks, no gradients: stands in for a real cover.
    private static func demoArtwork() -> UIImage {
        let size = CGSize(width: 1000, height: 1000)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(hex: 0x1E2A3A).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: 0xE8C547).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 180, y: 160, width: 420, height: 420))
            UIColor(hex: 0xD9534F).setFill()
            ctx.fill(CGRect(x: 0, y: 640, width: 1000, height: 120))
            UIColor(hex: 0xF2F1EE).setFill()
            ctx.fill(CGRect(x: 0, y: 790, width: 1000, height: 40))
            UIColor(hex: 0x3D7BF2).setFill()
            ctx.fill(CGRect(x: 640, y: 120, width: 220, height: 400))
        }
    }

    private static func demoIcon() -> UIImage {
        let size = CGSize(width: 120, height: 120)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(hex: 0x1ED760).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            ctx.cgContext.setLineWidth(9)
            ctx.cgContext.setLineCap(.round)
            for (i, y) in [42.0, 62, 80].enumerated() {
                let inset = 26.0 + Double(i) * 6
                ctx.cgContext.move(to: CGPoint(x: inset, y: y))
                ctx.cgContext.addQuadCurve(to: CGPoint(x: 120 - inset, y: y + 4), control: CGPoint(x: 60, y: y - 12))
                ctx.cgContext.strokePath()
            }
        }
    }

    /// The demo has no Mac: apply what a Mac would report after the tap.
    func demoEcho() {
        guard isDemo, var s = playback.mac else { return }
        let now = Date()
        s.isPlaying = playback.isPlaying(at: now)
        s.playbackRate = s.isPlaying ? 1 : 0
        s.elapsed = playback.position(at: now)
        s.shuffle = playback.shuffle(at: now)
        s.repeatMode = playback.repeatMode(at: now)
        s.outputs = playback.outputs(at: now)
        playback.receive(s, at: now)
    }
    #endif
}
