import Foundation
import Testing
@testable import GlasspadKit

@Suite struct MediaProtocolTests {
    func roundTrip(_ m: ModeMessage) throws -> ModeMessage {
        try JSONDecoder().decode(ModeMessage.self, from: JSONEncoder().encode(m))
    }

    @Test func controlsRoundTrip() throws {
        for c in [MediaControl.seek(42.5), .setShuffle(true), .setRepeat(.one), .selectOutput(id: "BuiltInSpeakerDevice")] {
            #expect(try roundTrip(.mediaControl(c)) == .mediaControl(c))
        }
        let json = String(decoding: try JSONEncoder().encode(ModeMessage.mediaControl(.seek(1))), as: UTF8.self)
        #expect(json.contains(#""t":"mediaControl""#))
    }

    @Test func richStateRoundTrips() throws {
        let state = MediaState(title: "T", artist: "A", album: "B", artworkPNG: Data([1]), isPlaying: true, duration: 200,
                               elapsed: 3, volume: 0.4, brightness: nil, playbackRate: 1, artworkID: "abc",
                               sourceBundleID: "com.spotify.client", sourceName: "Spotify", sourceIconPNG: Data([2]),
                               shuffle: true, repeatMode: .all, canSeek: true,
                               outputs: [MediaOutput(id: "u1", name: "MacBook Pro Speakers", kind: "builtIn", isCurrent: true)],
                               notice: MediaNotice(kind: MediaNotice.automationDenied, message: "Allow it", app: "Spotify"))
        #expect(try roundTrip(.mediaState(state)) == .mediaState(state))
    }

    @Test func olderMacStateStillDecodes() throws {
        let old = #"{"t":"mediaState","state":{"title":"Song","isPlaying":true,"volume":0.5}}"#
        let decoded = try JSONDecoder().decode(ModeMessage.self, from: Data(old.utf8))
        guard case .mediaState(let s) = decoded else { Issue.record("wrong case"); return }
        #expect(s.title == "Song")
        #expect(s.artworkID == nil)
        #expect(s.outputs == nil)
        #expect(s.notice == nil)
    }

    @Test func unknownRepeatModeReadsAsOff() throws {
        let json = #"{"isPlaying":false,"repeatMode":"shuffleRepeatLater"}"#
        let s = try JSONDecoder().decode(MediaState.self, from: Data(json.utf8))
        #expect(s.repeatMode == .off)
        #expect(MediaRepeatMode.off.next == .all)
        #expect(MediaRepeatMode.all.next == .one)
        #expect(MediaRepeatMode.one.next == .off)
    }
}
