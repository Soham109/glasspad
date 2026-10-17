import Foundation
import CoreGraphics
import Testing
@testable import GlasspadKit

@Suite("Touch codec")
struct TouchCodecTests {
    let surface = CGSize(width: 390, height: 844)

    func sample() -> TouchFrame {
        TouchFrame(seq: 4_000_000_001, timestamp: 12345.678901, touches: [
            Touch(id: 0, phase: .began, x: 0, y: 0, majorRadius: 20),
            Touch(id: 7, phase: .moved, x: 195.5, y: 422.25, majorRadius: 33),
            Touch(id: 255, phase: .ended, x: 390, y: 844, majorRadius: 510),
        ], surface: surface)
    }

    @Test func roundTripKeepsEveryField() throws {
        let f = sample()
        let data = TouchCodec.encode(f)
        #expect(data.count == TouchCodec.headerSize + 3 * TouchCodec.touchSize)
        let d = try TouchCodec.decode(data)
        #expect(d.seq == f.seq)
        #expect(abs(d.timestamp - f.timestamp) < 1e-6)
        #expect(d.surface == surface)
        #expect(d.touches.count == 3)
        for (a, b) in zip(d.touches, f.touches) {
            #expect(a.id == b.id)
            #expect(a.phase == b.phase)
            #expect(abs(a.x - b.x) < 0.01)
            #expect(abs(a.y - b.y) < 0.01)
        }
        #expect(d.touches[0].majorRadius == 20)
        #expect(d.touches[1].majorRadius == 34)        // stored as points / 2, rounded
        #expect(d.touches[2].majorRadius == 510)       // 255 * 2, the clamp ceiling
    }

    @Test func everyPhaseRoundTrips() throws {
        for p in [TouchPhase.began, .moved, .stationary, .ended, .cancelled] {
            let f = TouchFrame(seq: 1, timestamp: 1, touches: [Touch(id: 1, phase: p, x: 10, y: 10)], surface: surface)
            #expect(try TouchCodec.decode(TouchCodec.encode(f)).touches[0].phase == p)
        }
    }

    @Test func layoutIsLittleEndianAndCompact() {
        let f = TouchFrame(seq: 0x0102_0304, timestamp: 0.000_001, touches: [Touch(id: 9, phase: .moved, x: 390, y: 0)],
                           surface: surface)
        let b = [UInt8](TouchCodec.encode(f))
        #expect(b[0] == 1)
        #expect(Array(b[1...4]) == [0x04, 0x03, 0x02, 0x01])
        #expect(b[5] == 1 && b[6...12].allSatisfy { $0 == 0 })
        #expect(b[13] == 1)
        #expect(Array(b[14...15]) == [0x86, 0x01])      // 390
        #expect(b[18] == 9 && b[19] == 1)
        #expect(Array(b[20...21]) == [0xFF, 0xFF])      // x at full width
        #expect(b[25] == 0)
    }

    @Test func emptyFrameAndClamping() throws {
        let f = TouchFrame(seq: 2, timestamp: -5, touches: [Touch(id: 1, phase: .moved, x: -50, y: 9999, majorRadius: -3)],
                           surface: surface)
        let d = try TouchCodec.decode(TouchCodec.encode(f))
        #expect(d.timestamp == 0)
        #expect(d.touches[0].x == 0)
        #expect(abs(d.touches[0].y - 844) < 0.001)
        #expect(d.touches[0].majorRadius == 0)
        let empty = TouchFrame(seq: 3, timestamp: 1, touches: [], surface: surface)
        #expect(try TouchCodec.decode(TouchCodec.encode(empty)).touches.isEmpty)
    }

    @Test func moreThanTenTouchesAreTruncated() throws {
        let touches = (0..<12).map { Touch(id: UInt8($0), phase: .moved, x: Double($0), y: 1) }
        let d = try TouchCodec.decode(TouchCodec.encode(TouchFrame(seq: 1, timestamp: 1, touches: touches, surface: surface)))
        #expect(d.touches.count == 10)
    }

    @Test func heartbeat() throws {
        let data = TouchCodec.heartbeat(seq: 77, timestamp: 3.5)
        #expect(data.count == TouchCodec.headerSize)
        #expect(try TouchCodec.decodePacket(data) == .heartbeat(seq: 77, timestamp: 3.5))
        #expect(throws: TouchCodecError.notTouchPacket) { try TouchCodec.decode(data) }
    }

    @Test func malformedInputIsRejected() {
        let good = [UInt8](TouchCodec.encode(sample()))
        #expect(throws: TouchCodecError.tooShort) { try TouchCodec.decodePacket(Data()) }
        #expect(throws: TouchCodecError.tooShort) { try TouchCodec.decodePacket(Data(good.prefix(17))) }

        var kind = good; kind[0] = 9
        #expect(throws: TouchCodecError.unknownKind(9)) { try TouchCodec.decodePacket(Data(kind)) }

        var many = good; many[13] = 11
        #expect(throws: TouchCodecError.tooManyTouches(11)) { try TouchCodec.decodePacket(Data(many)) }

        #expect(throws: TouchCodecError.lengthMismatch(expected: good.count, actual: good.count - 1)) {
            try TouchCodec.decodePacket(Data(good.dropLast()))
        }
        #expect(throws: TouchCodecError.lengthMismatch(expected: good.count, actual: good.count + 1)) {
            try TouchCodec.decodePacket(Data(good + [0]))
        }
        var phase = good; phase[19] = 5
        #expect(throws: TouchCodecError.badPhase(5)) { try TouchCodec.decodePacket(Data(phase)) }

        var surf = good; surf[14] = 0; surf[15] = 0
        #expect(throws: TouchCodecError.emptySurface) { try TouchCodec.decodePacket(Data(surf)) }

        var dup = good; dup[26] = dup[18]
        #expect(throws: TouchCodecError.duplicateTouchID(dup[18])) { try TouchCodec.decodePacket(Data(dup)) }

        var hb = [UInt8](TouchCodec.heartbeat(seq: 1)); hb.append(0)
        #expect(throws: TouchCodecError.lengthMismatch(expected: 18, actual: 19)) { try TouchCodec.decodePacket(Data(hb)) }
    }

    @Test func randomBytesNeverCrash() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let n = Int.random(in: 0...120, using: &rng)
            let d = Data((0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) })
            _ = try? TouchCodec.decodePacket(d)
        }
    }
}

@Suite("Control messages")
struct ControlMessageTests {
    func roundTrip(_ m: ControlMessage) throws {
        let data = try m.jsonData()
        #expect(try ControlMessage.from(jsonData: data) == m)
    }

    @Test func everyCaseRoundTrips() throws {
        var s = TrackpadSettings.macDefault
        s.secondaryClick = .bottomLeft
        s.missionControl = .four
        for m: ControlMessage in [.ping(id: 1), .pong(id: UInt32.max), .settings(s), .haptic(.forceClick),
                                  .mode(.dockRequest), .bye(reason: "revoked")] {
            try roundTrip(m)
        }
    }

    @Test func usesTDiscriminator() throws {
        let json = String(decoding: try ControlMessage.ping(id: 5).jsonData(), as: UTF8.self)
        #expect(json.contains("\"t\":\"ping\""))
        #expect(json.contains("\"id\":5"))
        let m = try ControlMessage.from(jsonData: Data(#"{"t":"haptic","kind":"snap"}"#.utf8))
        #expect(m == .haptic(.snap))
        let bye = try ControlMessage.from(jsonData: Data(#"{"t":"bye","reason":"x"}"#.utf8))
        #expect(bye == .bye(reason: "x"))
    }

    @Test func unknownTypesDecodeAsNoOpButBrokenMessagesThrow() throws {
        // A newer build's message type: decodes so the receiver can ignore it and stay connected.
        #expect(try ControlMessage.from(jsonData: Data(#"{"t":"nope"}"#.utf8)) == .unknown(type: "nope"))
        #expect(try ControlMessage.from(jsonData: Data(#"{"t":"future","x":[1,2],"y":{"z":true}}"#.utf8))
                == .unknown(type: "future"))
        #expect(throws: (any Error).self) { try ControlMessage.from(jsonData: Data(#"{"t":"ping"}"#.utf8)) }
        #expect(throws: (any Error).self) { try ControlMessage.from(jsonData: Data("not json".utf8)) }
        #expect(throws: (any Error).self) { try ControlMessage.from(jsonData: Data(#"{"id":1}"#.utf8)) }
    }

    @Test func macStatusRoundTripsWithItsWireShape() throws {
        let full = ControlMessage.macStatus(MacStatus(accessibilityTrusted: false, automationMedia: .denied,
                                                      macName: "Soham's MacBook Pro"))
        let json = String(decoding: try full.jsonData(), as: UTF8.self)
        #expect(json.contains(#""t":"macStatus""#))
        #expect(json.contains(#""accessibilityTrusted":false"#))
        #expect(json.contains(#""automationMedia":"denied""#))
        #expect(try ControlMessage.from(jsonData: full.jsonData()) == full)

        let bare = ControlMessage.macStatus(MacStatus(accessibilityTrusted: true))
        #expect(try ControlMessage.from(jsonData: bare.jsonData()) == bare)
        for state in [AutomationState.granted, .denied, .notDetermined, .notNeeded] {
            let m = ControlMessage.macStatus(MacStatus(accessibilityTrusted: true, automationMedia: state))
            #expect(try ControlMessage.from(jsonData: m.jsonData()) == m)
        }
    }

    /// A newer Mac may add fields or automation values; this build keeps what it knows.
    @Test func macStatusToleratesFieldsFromNewerMacs() throws {
        let json = #"{"t":"macStatus","status":{"accessibilityTrusted":true,"automationMedia":"partly","macName":"Mac","screenRecording":true}}"#
        let m = try ControlMessage.from(jsonData: Data(json.utf8))
        #expect(m == .macStatus(MacStatus(accessibilityTrusted: true, automationMedia: nil, macName: "Mac")))
        // The one required field missing is a broken message.
        #expect(throws: (any Error).self) {
            try ControlMessage.from(jsonData: Data(#"{"t":"macStatus","status":{"macName":"Mac"}}"#.utf8))
        }
    }

    /// What a build from before macStatus sees: its decoder has no "macStatus" case. Its receive
    /// path (`try? ControlMessage.from`) dropped any frame that failed to decode and kept the
    /// session, so the old shape is simulated by decoding the frame with the tag it does not know.
    @Test func buildsWithoutMacStatusIgnoreIt() throws {
        let wire = try ControlMessage.macStatus(MacStatus(accessibilityTrusted: false)).jsonData()
        let renamed = String(decoding: wire, as: UTF8.self).replacingOccurrences(of: "macStatus", with: "zzUnknown")
        #expect(try ControlMessage.from(jsonData: Data(renamed.utf8)) == .unknown(type: "zzUnknown"))
        // Older builds still find their messages unchanged after the addition.
        #expect(try ControlMessage.from(jsonData: Data(#"{"t":"haptic","kind":"snap"}"#.utf8)) == .haptic(.snap))
    }

    @Test func everyModeMessageRoundTrips() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let id = UUID()
        let all: [ModeMessage] = [
            .modeSelected(.present),
            .dockRequest,
            .dockList(apps: [DockApp(bundleID: "com.apple.Safari", name: "Safari", iconPNG: png, running: true, active: false),
                             DockApp(bundleID: "com.apple.mail", name: "Mail", running: false, active: false)]),
            .dockOpen(bundleID: "com.apple.Notes"),
            .keysText("héllo 👋"),
            .keysKeystroke(Keystroke(key: .character("c"), modifiers: [.command])),
            .keysKeystroke(Keystroke(key: .special(.left), modifiers: [.command, .shift, .option, .control])),
            .mediaRequest,
            .mediaState(MediaState(title: "Song", artist: "Band", album: nil, artworkPNG: png, isPlaying: true,
                                   duration: 200, elapsed: 12.5, volume: 0.4, brightness: nil)),
            .mediaCommand(.nextTrack),
            .mediaSetVolume(0.25),
            .mediaSetBrightness(1),
            .deckRequest,
            .deckButtons([DeckButton(id: id, title: "Safari", symbol: "safari", action: .openApp(bundleID: "com.apple.Safari")),
                          DeckButton(title: "Site", symbol: "globe", action: .openURL("https://example.com")),
                          DeckButton(title: "Run", symbol: "bolt", action: .runShortcut(name: "Focus")),
                          DeckButton(title: "Shot", symbol: "camera", action: .keystroke(Keystroke(key: .character("4"), modifiers: [.command, .shift]))),
                          DeckButton(title: "Sh", symbol: "terminal", action: .shellScript("echo hi"))]),
            .deckRun(id: id),
            .deckResult(id: id, ok: false, message: "failed"),
            .clipboardPush(.text("copied")),
            .clipboardPush(.imagePNG(png)),
            .clipboardPull,
            .clipboardContent(nil),
            .clipboardContent(.text("mac")),
            .presentNext,
            .presentPrevious,
            .presentLaser(on: true),
            .presentLaserPosition(x: 0.25, y: 0.75),
            .modeSelected(.macros),
            .macro(.listMacros),
        ]
        for m in all { try roundTrip(.mode(m)) }
    }

    static let summary = MacroSummary(id: UUID(), name: "Close tab", symbol: "xmark.square", color: "#FF453A",
                                      stepCount: 2, usesScripts: false)

    static var everyMacroMessage: [MacroMessage] {
        let id = UUID()
        let profile = ActiveProfileInfo(profileID: UUID(), name: "Safari", symbol: "safari", bundleID: "com.apple.Safari",
                                        macros: [summary])
        return [
            .listMacros,
            .run(macroID: id),
            .gesture(name: "fourFingerTap"),
            .cancelRun,
            .recordStart(windowRelative: true, keepTiming: false),
            .recordStop,
            .macroList(active: profile, all: [summary, MacroSummary(id: id, name: "Deploy", symbol: "terminal",
                                                                    color: "#30D158", stepCount: 9, usesScripts: true)]),
            .macroList(active: ActiveProfileInfo(profileID: nil, name: "All Macros", symbol: "square.grid.2x2",
                                                 bundleID: nil, macros: []), all: []),
            .activeProfileChanged(profile),
            .progress(MacroProgress(macroID: id, completedSteps: 1, totalSteps: 3, currentPath: [1, 0],
                                    currentSummary: "Press ⌘W")),
            .runFinished(macroID: id, outcome: .completed, message: nil, outputs: []),
            .runFinished(macroID: id, outcome: .failed, message: "No app with bundle id x", outputs: ["out 1", "out 2"]),
            .runFinished(macroID: id, outcome: .interruptedByUser, message: nil, outputs: []),
            .runFinished(macroID: id, outcome: .cancelled, message: nil, outputs: []),
            .recordingState(isRecording: true),
            .recordingFinished(macro: summary, droppedSecureKeys: 3),
            .recordingFailed(message: "A password field is focused"),
        ]
    }

    @Test func everyMacroMessageRoundTrips() throws {
        for m in Self.everyMacroMessage { try roundTrip(.mode(.macro(m))) }
    }

    @Test func modeAndMacroMessagesUseTDiscriminator() throws {
        let id = UUID(uuidString: "6B1F3C2E-9D3A-4C55-8E21-0F8A6B3C9D11")!
        let json = String(decoding: try ControlMessage.mode(.macro(.run(macroID: id))).jsonData(), as: UTF8.self)
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        #expect(obj["t"] as? String == "mode")
        let mode = obj["mode"] as! [String: Any]
        #expect(mode["t"] as? String == "macro")
        let macro = mode["macro"] as! [String: Any]
        #expect(macro["t"] as? String == "run")
        #expect(macro["macroID"] as? String == id.uuidString)

        let open = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ModeMessage.dockOpen(bundleID: "com.apple.Notes"))) as! [String: Any]
        #expect(open as NSDictionary == ["t": "dockOpen", "bundleID": "com.apple.Notes"] as NSDictionary)
        let req = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ModeMessage.deckRequest)) as! [String: Any]
        #expect(req as NSDictionary == ["t": "deckRequest"] as NSDictionary)
        let text = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ModeMessage.keysText("hi"))) as! [String: Any]
        #expect(text as NSDictionary == ["t": "keysText", "text": "hi"] as NSDictionary)
        // A nil clipboard leaves the field out.
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ModeMessage.clipboardContent(nil))) as! [String: Any]
        #expect(empty as NSDictionary == ["t": "clipboardContent"] as NSDictionary)
    }

    @Test func legacySynthesizedModeMessagesStillDecode() throws {
        let id = UUID()
        let cases: [(String, ModeMessage)] = [
            (#"{"dockRequest":{}}"#, .dockRequest),
            (#"{"dockOpen":{"bundleID":"com.apple.Notes"}}"#, .dockOpen(bundleID: "com.apple.Notes")),
            (#"{"modeSelected":{"_0":"present"}}"#, .modeSelected(.present)),
            (#"{"keysText":{"_0":"héllo"}}"#, .keysText("héllo")),
            (#"{"mediaSetVolume":{"_0":0.5}}"#, .mediaSetVolume(0.5)),
            (#"{"mediaCommand":{"_0":"nextTrack"}}"#, .mediaCommand(.nextTrack)),
            (#"{"deckRun":{"id":"\#(id.uuidString)"}}"#, .deckRun(id: id)),
            (#"{"deckResult":{"id":"\#(id.uuidString)","ok":false,"message":"x"}}"#, .deckResult(id: id, ok: false, message: "x")),
            (#"{"clipboardContent":{}}"#, .clipboardContent(nil)),
            (#"{"clipboardPush":{"_0":{"text":{"_0":"copied"}}}}"#, .clipboardPush(.text("copied"))),
            (#"{"presentLaserPosition":{"x":0.25,"y":1}}"#, .presentLaserPosition(x: 0.25, y: 1)),
            (#"{"keysKeystroke":{"_0":{"key":{"character":{"_0":"c"}},"modifiers":1}}}"#,
             .keysKeystroke(Keystroke(key: .character("c"), modifiers: [.command]))),
        ]
        for (json, expected) in cases {
            #expect(try JSONDecoder().decode(ModeMessage.self, from: Data(json.utf8)) == expected, "\(json)")
        }
    }

    @Test func brokenModeMessagesThrow() {
        for json in [#"{"t":"nope"}"#, #"{"t":"dockOpen"}"#, #"{}"#, #"{"a":{},"b":{}}"#, #"{"t":"macro","macro":{"t":"zzz"}}"#,
                     #"{"t":"macro","macro":{"t":"run"}}"#] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(ModeMessage.self, from: Data(json.utf8)) }
        }
    }

    @Test func macroMessageDefaultsForOptionalFields() throws {
        let id = UUID()
        let m = try JSONDecoder().decode(MacroMessage.self, from: Data(#"{"t":"runFinished","macroID":"\#(id.uuidString)","outcome":"completed"}"#.utf8))
        #expect(m == .runFinished(macroID: id, outcome: .completed, message: nil, outputs: []))
        let r = try JSONDecoder().decode(MacroMessage.self, from: Data(#"{"t":"recordStart"}"#.utf8))
        #expect(r == .recordStart(windowRelative: false, keepTiming: true))
    }

    @Test func summaryColourAndProgressFraction() {
        let rgb = Self.summary.rgb
        #expect(rgb?.red == 1)
        #expect(abs((rgb?.green ?? 0) - 69.0 / 255) < 1e-9)
        #expect(abs((rgb?.blue ?? 0) - 58.0 / 255) < 1e-9)
        var bad = Self.summary
        for c in ["red", "#12345", "#GGGGGG", ""] {
            bad.color = c
            #expect(bad.rgb == nil)
        }
        bad.color = "00ff00"
        #expect(bad.rgb?.green == 1)
        #expect(MacroProgress(macroID: UUID(), completedSteps: 1, totalSteps: 4, currentPath: [], currentSummary: "").fraction == 0.25)
        #expect(MacroProgress(macroID: UUID(), completedSteps: 0, totalSteps: 0, currentPath: [], currentSummary: "").fraction == 1)
        #expect(GlasspadMode.allCases.contains(.macros))
    }

    @Test func settingsRoundTripAllEnums() throws {
        for sc in SecondaryClick.allCases {
            for lu in LookUp.allCases {
                var s = TrackpadSettings.macDefault
                s.secondaryClick = sc
                s.lookUp = lu
                s.swipeBetweenPages = .twoOrThree
                s.clickPressure = .firm
                try roundTrip(.settings(s))
            }
        }
    }

    /// Protocol 1, as 0.2.x phones and Macs still send it.
    @Test func handshakeShapesMatchSpec() throws {
        let hello = PhoneHello(v: 1, phoneID: "p", phoneName: "Phone", macID: UUID(), nonce: Data(repeating: 1, count: 16))
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(hello)) as! [String: Any]
        #expect(obj["t"] as? String == "hello")
        #expect(obj["v"] as? Int == 1)
        #expect(Set(obj.keys) == ["t", "v", "phoneID", "phoneName", "macID", "nonce"])
        let mac = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MacHello(v: 1, nonce: Data(count: 16), udpPort: 9))) as! [String: Any]
        #expect(Set(mac.keys) == ["t", "v", "nonce", "udpPort"])
    }

    /// Protocol 2 adds the X25519 public keys and the rekey flag.
    @Test func protocol2HandshakeShapes() throws {
        let hello = PhoneHello(phoneID: "p", phoneName: "Phone", macID: UUID(), nonce: Data(repeating: 1, count: 16),
                               kx: Data(repeating: 9, count: 32), rekey: true)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(hello)) as! [String: Any]
        #expect(obj["v"] as? Int == 2)
        #expect(Set(obj.keys) == ["t", "v", "phoneID", "phoneName", "macID", "nonce", "kx", "rekey"])
        let agreed = PhoneHello(phoneID: "p", phoneName: "Phone", macID: UUID(), nonce: Data(count: 16), kx: Data(count: 32))
        let agreedObj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(agreed)) as! [String: Any]
        #expect(Set(agreedObj.keys) == ["t", "v", "phoneID", "phoneName", "macID", "nonce", "kx"])
        let mac = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            MacHello(nonce: Data(count: 16), udpPort: 9, kx: Data(count: 32), rekey: false))) as! [String: Any]
        #expect(Set(mac.keys) == ["t", "v", "nonce", "udpPort", "kx", "rekey"])
        #expect(mac["v"] as? Int == 2)
    }

    @Test func frameAccumulatorSplitsAndJoins() throws {
        var acc = FrameAccumulator()
        let a = Data("first".utf8), b = Data(repeating: 7, count: 70_000), c = Data()
        let stream = FrameAccumulator.wrap(a) + FrameAccumulator.wrap(b) + FrameAccumulator.wrap(c)
        var out: [Data] = []
        var i = stream.startIndex
        while i < stream.endIndex {          // feed in odd-sized chunks
            let j = min(i + 333, stream.endIndex)
            out += try acc.append(Data(stream[i..<j]))
            i = j
        }
        #expect(out == [a, b, c])
        var bad = FrameAccumulator()
        #expect(throws: (any Error).self) { try bad.append(Data([0xFF, 0xFF, 0xFF, 0xFF])) }
    }
}
