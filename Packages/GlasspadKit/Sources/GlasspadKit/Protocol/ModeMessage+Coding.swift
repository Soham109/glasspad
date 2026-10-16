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

    /// A list, skipping only the elements this build cannot read.
    func lenientArray<T: Decodable>(_ type: T.Type, _ name: String, unlabeled: Bool = false) throws -> [T] {
        try c.decodeLenientArray(T.self, forKey: key(name, unlabeled: unlabeled))
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
        case "modesShown":
            // A screen from a newer build is skipped, not a reason to drop the rest.
            self = .modesShown(try f.value([String].self, "modes").compactMap(GlasspadMode.init(rawValue:)))
        case "dockRequest": self = .dockRequest
        case "dockList": self = .dockList(apps: try f.value([DockApp].self, "apps"))
        case "dockOpen": self = .dockOpen(bundleID: try f.value(String.self, "bundleID"))
        case "dockSync": self = .dockSync(iconKeys: try f.value([String].self, "iconKeys"))
        case "dockAppAction":
            self = .dockAppAction(bundleID: try f.value(String.self, "bundleID"), action: try f.value(DockAppAction.self, "action"))
        case "dockOpenResult":
            self = .dockOpenResult(bundleID: try f.value(String.self, "bundleID"), ok: try f.value(Bool.self, "ok"),
                                   message: try f.optional(String.self, "message"))
        case "dockCatalogRequest": self = .dockCatalogRequest
        case "dockCatalog": self = .dockCatalog(apps: try f.value([DockApp].self, "apps"))
        case "dockIconRequest": self = .dockIconRequest(bundleIDs: try f.value([String].self, "bundleIDs"))
        case "dockIcons": self = .dockIcons(apps: try f.value([DockApp].self, "apps"))
        case "frontmostApp": self = .frontmostApp(bundleID: try f.optional(String.self, "bundleID"))
        case "macDockState": self = .macDockState(try f.value(MacDockState.self, "state", unlabeled: true))
        case "macDockSet": self = .macDockSet(try f.value(MacDockState.self, "state", unlabeled: true))
        case "keysText": self = .keysText(try f.value(String.self, "text", unlabeled: true))
        case "keysKeystroke": self = .keysKeystroke(try f.value(Keystroke.self, "keystroke", unlabeled: true))
        case "mediaRequest": self = .mediaRequest
        case "mediaState": self = .mediaState(try f.value(MediaState.self, "state", unlabeled: true))
        case "mediaCommand": self = .mediaCommand(try f.value(MediaCommand.self, "command", unlabeled: true))
        case "mediaSetVolume": self = .mediaSetVolume(try f.value(Double.self, "value", unlabeled: true))
        case "mediaSetBrightness": self = .mediaSetBrightness(try f.value(Double.self, "value", unlabeled: true))
        case "mediaControl": self = .mediaControl(try f.value(MediaControl.self, "control", unlabeled: true))
        case "deckRequest": self = .deckRequest
        case "deckButtons": self = .deckButtons(try f.lenientArray(DeckButton.self, "buttons", unlabeled: true))
        case "deckRun": self = .deckRun(id: try f.value(UUID.self, "id"))
        case "deckResult":
            self = .deckResult(id: try f.value(UUID.self, "id"), ok: try f.value(Bool.self, "ok"),
                               message: try f.optional(String.self, "message"))
        case "deckLayout": self = .deckLayout(try f.value(DeckLayout.self, "layout", unlabeled: true))
        case "deckSave": self = .deckSave(try f.value(DeckLayout.self, "layout", unlabeled: true))
        case "deckSaveResult":
            self = .deckSaveResult(ok: try f.value(Bool.self, "ok"), message: try f.optional(String.self, "message"))
        case "deckRunConfirmed": self = .deckRunConfirmed(id: try f.value(UUID.self, "id"))
        case "deckCatalogRequest": self = .deckCatalogRequest
        case "deckCatalog": self = .deckCatalog(try f.value(DeckCatalog.self, "catalog", unlabeled: true))
        case "deckImage":
            self = .deckImage(id: try f.value(UUID.self, "id"), imageData: try f.value(Data.self, "imageData"),
                              destination: try f.value(DeckImageDestination.self, "destination"))
        case "clipboardPush": self = .clipboardPush(try f.value(ClipboardContent.self, "content", unlabeled: true))
        case "clipboardPull": self = .clipboardPull
        case "clipboardContent": self = .clipboardContent(try f.optional(ClipboardContent.self, "content", unlabeled: true))
        case "clipboardPushResult":
            self = .clipboardPushResult(ok: try f.value(Bool.self, "ok"), message: try f.optional(String.self, "message"))
        case "clipboardPullRefused": self = .clipboardPullRefused(message: try f.value(String.self, "message"))
        case "presentNext": self = .presentNext
        case "presentPrevious": self = .presentPrevious
        case "presentLaser": self = .presentLaser(on: try f.value(Bool.self, "on"))
        case "presentLaserPosition":
            self = .presentLaserPosition(x: try f.value(Double.self, "x"), y: try f.value(Double.self, "y"))
        case "remoteSystem":
            self = .remoteSystem(id: try f.value(UUID.self, "id"), action: try f.value(DeckSystemAction.self, "action"))
        case "displaysWatch": self = .displaysWatch(on: try f.value(Bool.self, "on"))
        case "displaysState": self = .displaysState(try f.value(DisplaysState.self, "state"))
        case "windowCommand":
            self = .windowCommand(id: try f.value(UUID.self, "id"), windowID: try f.value(UInt32.self, "windowID"),
                                  command: try f.value(WindowCommand.self, "command"))
        case "displayCommand":
            self = .displayCommand(id: try f.value(UUID.self, "id"), command: try f.value(DisplayCommand.self, "command"))
        case "displaysResult":
            self = .displaysResult(id: try f.value(UUID.self, "id"), ok: try f.value(Bool.self, "ok"),
                                   message: try f.optional(String.self, "message"))
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
        case .modesShown(let modes): try put(modes, "modes")
        case .dockList(let apps): try put(apps, "apps")
        case .dockOpen(let id): try put(id, "bundleID")
        case .dockSync(let keys): try put(keys, "iconKeys")
        case .dockAppAction(let id, let action):
            try put(id, "bundleID")
            try put(action, "action")
        case .dockOpenResult(let id, let ok, let message):
            try put(id, "bundleID")
            try put(ok, "ok")
            try c.encodeIfPresent(message, forKey: AnyCodingKey("message"))
        case .dockCatalog(let apps), .dockIcons(let apps): try put(apps, "apps")
        case .dockIconRequest(let ids): try put(ids, "bundleIDs")
        case .frontmostApp(let id): try c.encodeIfPresent(id, forKey: AnyCodingKey("bundleID"))
        case .macDockState(let s), .macDockSet(let s): try put(s, "state")
        case .deckLayout(let l), .deckSave(let l): try put(l, "layout")
        case .deckSaveResult(let ok, let message):
            try put(ok, "ok")
            try c.encodeIfPresent(message, forKey: AnyCodingKey("message"))
        case .deckRunConfirmed(let id): try put(id, "id")
        case .deckCatalog(let catalog): try put(catalog, "catalog")
        case .deckImage(let id, let data, let destination):
            try put(id, "id")
            try put(data, "imageData")
            try put(destination, "destination")
        case .keysText(let text): try put(text, "text")
        case .keysKeystroke(let k): try put(k, "keystroke")
        case .mediaState(let s): try put(s, "state")
        case .mediaCommand(let cmd): try put(cmd, "command")
        case .mediaSetVolume(let v), .mediaSetBrightness(let v): try put(v, "value")
        case .mediaControl(let control): try put(control, "control")
        case .deckButtons(let b): try put(b, "buttons")
        case .deckRun(let id): try put(id, "id")
        case .deckResult(let id, let ok, let message):
            try put(id, "id")
            try put(ok, "ok")
            try c.encodeIfPresent(message, forKey: AnyCodingKey("message"))
        case .clipboardPush(let content): try put(content, "content")
        case .clipboardContent(let content): try c.encodeIfPresent(content, forKey: AnyCodingKey("content"))
        case .clipboardPushResult(let ok, let message):
            try put(ok, "ok")
            try c.encodeIfPresent(message, forKey: AnyCodingKey("message"))
        case .clipboardPullRefused(let message): try put(message, "message")
        case .presentLaser(let on): try put(on, "on")
        case .presentLaserPosition(let x, let y):
            try put(x, "x")
            try put(y, "y")
        case .remoteSystem(let id, let action):
            try put(id, "id")
            try put(action, "action")
        case .displaysWatch(let on): try put(on, "on")
        case .displaysState(let state): try put(state, "state")
        case .windowCommand(let id, let windowID, let command):
            try put(id, "id")
            try put(windowID, "windowID")
            try put(command, "command")
        case .displayCommand(let id, let command):
            try put(id, "id")
            try put(command, "command")
        case .displaysResult(let id, let ok, let message):
            try put(id, "id")
            try put(ok, "ok")
            try c.encodeIfPresent(message, forKey: AnyCodingKey("message"))
        case .macro(let m): try put(m, "macro")
        case .dockRequest, .mediaRequest, .deckRequest, .clipboardPull, .presentNext, .presentPrevious,
             .dockCatalogRequest, .deckCatalogRequest:
            break
        }
    }

    /// The `"t"` value for this case.
    var tag: String {
        switch self {
        case .modeSelected: "modeSelected"
        case .modesShown: "modesShown"
        case .dockRequest: "dockRequest"
        case .dockList: "dockList"
        case .dockOpen: "dockOpen"
        case .dockSync: "dockSync"
        case .dockAppAction: "dockAppAction"
        case .dockOpenResult: "dockOpenResult"
        case .dockCatalogRequest: "dockCatalogRequest"
        case .dockCatalog: "dockCatalog"
        case .dockIconRequest: "dockIconRequest"
        case .dockIcons: "dockIcons"
        case .frontmostApp: "frontmostApp"
        case .macDockState: "macDockState"
        case .macDockSet: "macDockSet"
        case .deckLayout: "deckLayout"
        case .deckSave: "deckSave"
        case .deckSaveResult: "deckSaveResult"
        case .deckRunConfirmed: "deckRunConfirmed"
        case .deckCatalogRequest: "deckCatalogRequest"
        case .deckCatalog: "deckCatalog"
        case .deckImage: "deckImage"
        case .keysText: "keysText"
        case .keysKeystroke: "keysKeystroke"
        case .mediaRequest: "mediaRequest"
        case .mediaState: "mediaState"
        case .mediaCommand: "mediaCommand"
        case .mediaSetVolume: "mediaSetVolume"
        case .mediaSetBrightness: "mediaSetBrightness"
        case .mediaControl: "mediaControl"
        case .deckRequest: "deckRequest"
        case .deckButtons: "deckButtons"
        case .deckRun: "deckRun"
        case .deckResult: "deckResult"
        case .clipboardPush: "clipboardPush"
        case .clipboardPull: "clipboardPull"
        case .clipboardContent: "clipboardContent"
        case .clipboardPushResult: "clipboardPushResult"
        case .clipboardPullRefused: "clipboardPullRefused"
        case .presentNext: "presentNext"
        case .presentPrevious: "presentPrevious"
        case .presentLaser: "presentLaser"
        case .presentLaserPosition: "presentLaserPosition"
        case .remoteSystem: "remoteSystem"
        case .displaysWatch: "displaysWatch"
        case .displaysState: "displaysState"
        case .windowCommand: "windowCommand"
        case .displayCommand: "displayCommand"
        case .displaysResult: "displaysResult"
        case .macro: "macro"
        }
    }
}
