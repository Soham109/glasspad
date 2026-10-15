import AppKit
import AudioToolbox
import CoreAudio
import GlasspadKit

/// Media mode: now playing via MediaRemote (private, loaded with dlopen), transport commands
/// with a media-key fallback, output volume via CoreAudio, display brightness via
/// DisplayServices (private, dlopen) when present.
///
/// Note: since macOS 15.4 MediaRemote only returns now-playing info to Apple-entitled
/// processes, so title/artist may come back empty for Glasspad; commands still work, and the
/// media-key fallback always does.
@MainActor
public final class MediaMode {
    private let poster: EventPoster
    private let remote = MediaRemote.shared

    public init(poster: EventPoster) { self.poster = poster }

    public func send(_ command: MediaCommand) {
        if command == .mute {
            toggleMute()
            return
        }
        if remote.send(command) { return }
        if let key = Self.mediaKey(for: command) { postMediaKey(key) }
    }

    /// NX_KEYTYPE_* values (IOKit hidsystem ev_keymap.h, public): play 16, next 17, previous 18.
    nonisolated static func mediaKey(for command: MediaCommand) -> Int32? {
        switch command {
        case .playPause, .play, .pause: 16
        case .nextTrack: 17
        case .previousTrack: 18
        case .mute: 7
        }
    }

    /// Media keys are NSSystemDefined events, subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS), with
    /// data1 = key << 16 | (0xA down or 0xB up) << 8. Public AppKit + ev_keymap.h values.
    nonisolated static func mediaKeyEvents(_ key: Int32) -> [CGEvent] {
        [true, false].compactMap { down in
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            return NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                      windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent
        }
    }

    private func postMediaKey(_ key: Int32) {
        Self.mediaKeyEvents(key).forEach { poster.post($0, tap: .cghidEventTap) }
    }

    public func state(completion: @escaping @MainActor (MediaState) -> Void) {
        let volume = AudioOutput.volume()
        let brightness = Brightness.get()
        remote.nowPlaying { info in
            var s = MediaState(volume: volume.map(Double.init), brightness: brightness.map(Double.init))
            if let info {
                s.title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
                s.artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
                s.album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
                s.duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double
                s.elapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double
                s.isPlaying = ((info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double) ?? 0) > 0
                if let art = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, let image = NSImage(data: art) {
                    s.artworkPNG = DockMode.renderPNG(image, pixels: 256)
                }
            }
            completion(s)
        }
    }

    public func setVolume(_ v: Double) { AudioOutput.setVolume(Float(min(1, max(0, v)))) }
    public func setBrightness(_ v: Double) { Brightness.set(Float(min(1, max(0, v)))) }

    private func toggleMute() {
        if let muted = AudioOutput.isMuted() { AudioOutput.setMuted(!muted) }
    }
}

/// MediaRemote.framework, loaded at runtime. Symbol names are long-standing and widely used
/// (e.g. by open-source now-playing tools); every call checks the symbol exists.
final class MediaRemote: @unchecked Sendable {
    static let shared = MediaRemote()

    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void

    private let sendCommand: SendCommandFn?
    private let getInfo: GetInfoFn?

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        sendCommand = handle.flatMap { dlsym($0, "MRMediaRemoteSendCommand") }.map { unsafeBitCast($0, to: SendCommandFn.self) }
        getInfo = handle.flatMap { dlsym($0, "MRMediaRemoteGetNowPlayingInfo") }.map { unsafeBitCast($0, to: GetInfoFn.self) }
    }

    var available: Bool { sendCommand != nil }

    /// MRMediaRemoteCommand values: play 0, pause 1, togglePlayPause 2, nextTrack 4, previousTrack 5.
    func send(_ c: MediaCommand) -> Bool {
        let code: Int32
        switch c {
        case .play: code = 0
        case .pause: code = 1
        case .playPause: code = 2
        case .nextTrack: code = 4
        case .previousTrack: code = 5
        case .mute: return false
        }
        return sendCommand?(code, nil) ?? false
    }

    func nowPlaying(_ done: @escaping @MainActor ([String: Any]?) -> Void) {
        guard let getInfo else {
            Task { @MainActor in done(nil) }
            return
        }
        getInfo(DispatchQueue.main) { dict in
            nonisolated(unsafe) let info = dict as? [String: Any]
            MainActor.assumeIsolated { done(info) }
        }
    }
}

/// Default output device volume and mute through CoreAudio (public).
enum AudioOutput {
    static func defaultDevice() -> AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    static func volume() -> Float? {
        guard let dev = defaultDevice() else { return nil }
        var addr = volumeAddress
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func setVolume(_ v: Float) {
        guard let dev = defaultDevice() else { return }
        var addr = volumeAddress
        var value = Float32(v)
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func isMuted() -> Bool? {
        guard let dev = defaultDevice() else { return nil }
        var addr = muteAddress
        var v = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr ? v != 0 : nil
    }

    static func setMuted(_ muted: Bool) {
        guard let dev = defaultDevice() else { return }
        var addr = muteAddress
        var v = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }
}

/// Main display brightness through DisplayServices.framework (private, dlopen). Returns nil when
/// the framework or display does not support it (external monitors usually do not).
enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private nonisolated(unsafe) static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static func get() -> Float? {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        var v: Float = 0
        return unsafeBitCast(sym, to: GetFn.self)(CGMainDisplayID(), &v) == 0 ? v : nil
    }

    static func set(_ v: Float) {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return }
        _ = unsafeBitCast(sym, to: SetFn.self)(CGMainDisplayID(), v)
    }
}
