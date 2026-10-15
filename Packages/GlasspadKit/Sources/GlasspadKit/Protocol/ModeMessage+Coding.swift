import Foundation

/// A coding key made from any string (the `"t"`-style messages and the legacy shape).
struct AnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Reads the fields of one case. In the legacy (synthesized) shape an unlabeled payload is
/// stored under `_0`; `unlabeled: true` reads it from there.
private struct CaseFields {
    let c: KeyedDecodingContainer<AnyCodingKey>
    let legacy: Bool

    func key(_ name: String, unlabeled: Bool) -> AnyCodingKey { AnyCodingKey(legacy && unlabeled ? "_0" : name) }

    func value<T: Decodable>(_ type: T.Type, _ name: String, unlabeled: Bool = false) throws -> T {
        try c.decode(T.self, forKey: key(name, unlabeled: unlabeled))
    }

    func optional<T: Decodable>(_ type: T.Type, _ name: String, unlabeled: Bool = false) throws -> T? {
        try c.decodeIfPresent(T.self, forKey: key(name, unlabeled: unlabeled))
    }
}

extension ModeMessage {
    public init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: AnyCodingKey.self)
        let tagKey = AnyCodingKey("t")
        let fields: CaseFields
        let tag: String
        if top.contains(tagKey) {
            tag = try top.decode(String.self, forKey: tagKey)
            fields = CaseFields(c: top, legacy: false)
        } else if top.allKeys.count == 1, let only = top.allKeys.first {
            // Legacy synthesized shape: {"caseName":{...}}.
            tag = only.stringValue
            fields = CaseFields(c: try top.nestedContainer(keyedBy: AnyCodingKey.self, forKey: only), legacy: true)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "mode message without a \"t\" field"))
        }
        let f = fields
        switch tag {
        case "modeSelected": self = .modeSelected(try f.value(GlasspadMode.self, "mode", unlabeled: true))
        case "dockRequest": self = .dockRequest
        case "dockList": self = .dockList(apps: try f.value([DockApp].self, "apps"))
        case "dockOpen": self = .dockOpen(bundleID: try f.value(String.self, "bundleID"))
        case "keysText": self = .keysText(try f.value(String.self, "text", unlabeled: true))
        case "keysKeystroke": self = .keysKeystroke(try f.value(Keystroke.self, "keystroke", unlabeled: true))
        case "mediaRequest": self = .mediaRequest
        case "mediaState": self = .mediaState(try f.value(MediaState.self, "state", unlabeled: true))
        case "mediaCommand": self = .mediaCommand(try f.value(MediaCommand.self, "command", unlabeled: true))
        case "mediaSetVolume": self = .mediaSetVolume(try f.value(Double.self, "value", unlabeled: true))
        case "mediaSetBrightness": self = .mediaSetBrightness(try f.value(Double.self, "value", unlabeled: true))
        case "deckRequest": self = .deckRequest
        case "deckButtons": self = .deckButtons(try f.value([DeckButton].self, "buttons", unlabeled: true))
        case "deckRun": self = .deckRun(id: try f.value(UUID.self, "id"))
        case "deckResult":
            self = .deckResult(id: try f.value(UUID.self, "id"), ok: try f.value(Bool.self, "ok"),
                               message: try f.optional(String.self, "message"))
        case "clipboardPush": self = .clipboardPush(try f.value(ClipboardContent.self, "content", unlabeled: true))
        case "clipboardPull": self = .clipboardPull
        case "clipboardContent": self = .clipboardContent(try f.optional(ClipboardContent.self, "content", unlabeled: true))
        case "presentNext": self = .presentNext
        case "presentPrevious": self = .presentPrevious
        case "presentLaser": self = .presentLaser(on: try f.value(Bool.self, "on"))
        case "presentLaserPosition":
            self = .presentLaserPosition(x: try f.value(Double.self, "x"), y: try f.value(Double.self, "y"))
        case "macro": self = .macro(try f.value(MacroMessage.self, "macro", unlabeled: true))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "unknown mode message \(tag)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        func put<T: Encodable>(_ v: T, _ name: String) throws { try c.encode(v, forKey: AnyCodingKey(name)) }
        try put(tag, "t")
        switch self {
        case .modeSelected(let m): try put(m, "mode")
        case .dockList(let apps): try put(apps, "apps")
        case .dockOpen(let id): try put(id, "bundleID")
        case .keysText(let text): try put(text, "text")
        case .keysKeystroke(let k): try put(k, "keystroke")
        case .mediaState(let s): try put(s, "state")
        case .mediaCommand(let cmd): try put(cmd, "command")
        case .mediaSetVolume(let v), .mediaSetBrightness(let v): try put(v, "value")
        case .deckButtons(let b): try put(b, "buttons")
        case .deckRun(let id): try put(id, "id")
        case .deckResult(let id, let ok, let message):
            try put(id, "id")
            try put(ok, "ok")
            try c.encodeIfPresent(message, forKey: AnyCodingKey("message"))
        case .clipboardPush(let content): try put(content, "content")
        case .clipboardContent(let content): try c.encodeIfPresent(content, forKey: AnyCodingKey("content"))
        case .presentLaser(let on): try put(on, "on")
        case .presentLaserPosition(let x, let y):
            try put(x, "x")
            try put(y, "y")
        case .macro(let m): try put(m, "macro")
        case .dockRequest, .mediaRequest, .deckRequest, .clipboardPull, .presentNext, .presentPrevious:
            break
        }
    }

    /// The `"t"` value for this case.
    var tag: String {
        switch self {
        case .modeSelected: "modeSelected"
        case .dockRequest: "dockRequest"
        case .dockList: "dockList"
        case .dockOpen: "dockOpen"
        case .keysText: "keysText"
        case .keysKeystroke: "keysKeystroke"
        case .mediaRequest: "mediaRequest"
        case .mediaState: "mediaState"
        case .mediaCommand: "mediaCommand"
        case .mediaSetVolume: "mediaSetVolume"
        case .mediaSetBrightness: "mediaSetBrightness"
        case .deckRequest: "deckRequest"
        case .deckButtons: "deckButtons"
        case .deckRun: "deckRun"
        case .deckResult: "deckResult"
        case .clipboardPush: "clipboardPush"
        case .clipboardPull: "clipboardPull"
        case .clipboardContent: "clipboardContent"
        case .presentNext: "presentNext"
        case .presentPrevious: "presentPrevious"
        case .presentLaser: "presentLaser"
        case .presentLaserPosition: "presentLaserPosition"
        case .macro: "macro"
        }
    }
}
