import CoreGraphics
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// Feeds frames from the real server straight into a real TouchPipeline (main actor), like
/// GlasspadController does.
private final class PipelineBridge: GlasspadLinkDelegate {
    let pipeline: TouchPipeline
    init(_ pipeline: TouchPipeline) { self.pipeline = pipeline }
    func link(didChangeState state: LinkState) {}
    func link(didReceive message: ControlMessage) {}
    func link(didReceive frame: TouchFrame) {
        let p = pipeline
        MainActor.assumeIsolated { p.process(frame) }
    }
}

/// Phone to Mac through everything real: GlasspadClient -> sealed UDP over loopback ->
/// GlasspadServer -> GestureRecognizer -> EventSynthesizer -> CapturingEventPoster (nothing is
/// posted to the session).
@Suite(.serialized) @MainActor struct LoopbackEndToEndTests {
    let surface = CGSize(width: 390, height: 844)

    struct Rig {
        let server: GlasspadServer
        let client: GlasspadClient
        let poster: CapturingEventPoster
        let pipeline: TouchPipeline
        fileprivate let bridge: PipelineBridge
        var haptics: () -> [HapticKind]
    }

    final class HapticLog { var items: [HapticKind] = [] }

    func makeRig(settings: TrackpadSettings) async throws -> Rig {
        let (synth, poster) = makeSynth(settings: settings)
        let pipeline = TouchPipeline(settings: settings, synth: synth)
        pipeline.setDisplayWidth(1512)
        let log = HapticLog()
        pipeline.onHaptic = { log.items.append($0) }
        let bridge = PipelineBridge(pipeline)
        let key = PairingPayload.generateKey()
        let macID = UUID()
        let server = GlasspadServer(macID: macID, macName: "Loopback Mac", advertise: false, delegateQueue: .main) { _ in key }
        server.delegate = bridge
        try server.start()
        #expect(await eventually { server.ports != nil })
        let port = try #require(server.ports).tcp
        let client = GlasspadClient(phoneID: "phone-e2e", phoneName: "Phone",
                                    pairing: PairingPayload(macID: macID, macName: "Loopback Mac", pairKey: key))
        client.connect(host: "127.0.0.1", port: port)
        #expect(await eventually { client.state == .connected(rttMs: nil) && server.connectedPhone != nil })
        return Rig(server: server, client: client, poster: poster, pipeline: pipeline, bridge: bridge, haptics: { log.items })
    }

    /// Sends one gesture as the phone would: a frame every 8 ms with real timestamps.
    func play(_ rig: Rig, fingers: [CGPoint], step: CGVector, frames: Int) async throws {
        func touches(_ i: Int, _ phase: TouchPhase) -> [Touch] {
            fingers.enumerated().map { n, p in
                Touch(id: UInt8(n + 1), phase: phase, x: p.x + step.dx * Double(i), y: p.y + step.dy * Double(i), majorRadius: 20)
            }
        }
        for i in 0...frames {
            rig.client.send(frame: TouchFrame(seq: 0, timestamp: ProcessInfo.processInfo.systemUptime,
                                              touches: touches(i, i == 0 ? .began : .moved), surface: surface))
            try await Task.sleep(nanoseconds: 8_000_000)
        }
        rig.client.send(frame: TouchFrame(seq: 0, timestamp: ProcessInfo.processInfo.systemUptime,
                                          touches: touches(frames, .ended), surface: surface))
    }

    @Test func twoFingerScrollArrivesAsPhasedPixelScroll() async throws {
        var settings = TrackpadSettings.macDefault
        settings.naturalScrolling = true
        settings.scrollMomentum = false
        let rig = try await makeRig(settings: settings)
        defer { rig.client.disconnect(); rig.server.stop() }

        // Two fingers side by side, moving up 6 pt per frame for 25 frames.
        try await play(rig, fingers: [CGPoint(x: 160, y: 600), CGPoint(x: 230, y: 600)], step: CGVector(dx: 0, dy: -6), frames: 25)
        #expect(await eventually {
            rig.poster.events.contains { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventScrollPhase) == 4 }
        })
        let scrolls = rig.poster.events.filter { $0.type == .scrollWheel }
        let phases = scrolls.map { $0.getIntegerValueField(.scrollWheelEventScrollPhase) }
        #expect(phases.first == 1)                                  // began
        #expect(phases.filter { $0 == 2 }.count >= 5)               // changed, following the fingers
        #expect(phases.last == 4)                                   // ended
        #expect(scrolls.allSatisfy { $0.getIntegerValueField(.scrollWheelEventIsContinuous) == 1 })
        #expect(scrolls.allSatisfy { $0.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 })
        // Natural scrolling: fingers up moves the content up, which is a negative (wheel down) delta.
        let dy = scrolls.map { $0.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) }
        #expect(dy.reduce(0, +) < -40)
        #expect(dy.allSatisfy { $0 <= 0 })
        let dx = scrolls.map { $0.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) }
        #expect(dx.allSatisfy { abs($0) < 0.001 })
        // A scroll is not a click or a pointer move.
        #expect(!rig.poster.events.contains { [.leftMouseDown, .rightMouseDown, .mouseMoved].contains($0.type) })
        #expect(rig.server.stats.authFailures == 0)
    }

    @Test func threeFingerSwipeDrivesSpacesAndSnaps() async throws {
        var settings = TrackpadSettings.macDefault
        settings.swipeBetweenSpaces = .three
        settings.swipeBetweenPages = .twoFinger
        settings.threeFingerDrag = false
        let rig = try await makeRig(settings: settings)
        defer { rig.client.disconnect(); rig.server.stop() }

        // Three fingers sweeping left 9 pt per frame for 30 frames (270 pt, most of the surface).
        try await play(rig, fingers: [CGPoint(x: 300, y: 380), CGPoint(x: 340, y: 420), CGPoint(x: 380, y: 400)],
                       step: CGVector(dx: -9, dy: 0), frames: 30)
        func dock(_ e: CGEvent) -> Bool { e.type.rawValue == 30 }
        #expect(await eventually { rig.poster.events.contains { dock($0) && $0.get(.gesturePhase) == 4 } })
        let immediate = rig.poster.posted.filter { $0.delay == 0 }.map(\.event)
        let docks = immediate.filter(dock)
        #expect(docks.first?.get(.gesturePhase) == 1)               // began
        #expect(docks.filter { $0.get(.gesturePhase) == 2 }.count >= 3)
        #expect(docks.last?.get(.gesturePhase) == 4)                // ended
        #expect(docks.allSatisfy { $0.get(.gestureHIDType) == 23 && $0.get(.dockSwipeMotion) == 1 })   // horizontal dock swipe
        // Every dock event rides with its type-29 companion.
        #expect(immediate.filter { $0.type.rawValue == 29 }.count == docks.count)
        // Progress grows as the fingers travel left, and the swipe completed (snap haptic).
        let offsets = docks.map { $0.getDouble(.dockSwipeOriginOffset) }
        #expect(offsets.last ?? 0 > 0.5)
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0.1 >= $0.0 - 1e-6 })
        #expect(rig.haptics() == [.snap])
        #expect(rig.poster.posted.allSatisfy { $0.tap == .cgSessionEventTap })
        // No pointer motion, clicks or page navigation leaked out of the swipe.
        #expect(!rig.poster.events.contains { [.leftMouseDown, .mouseMoved, .scrollWheel].contains($0.type) })
    }
}
