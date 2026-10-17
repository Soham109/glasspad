import AppKit
import Foundation
import GlasspadKit
import Testing
@testable import GlasspadMacCore

/// The Mac's side of the security review fixes (docs/security): agreed keys in the Keychain,
/// the Allow question, the copied link, password manager items and album artwork.
@Suite struct PairingSecurityTests {
    @Test func agreedKeysAreStoredAndOldEntriesReadAsCodeKeys() throws {
        let secrets = InMemorySecretStore()
        let store = PairingStore(store: secrets)
        let code = Data(repeating: 1, count: 32), agreed = Data(repeating: 2, count: 32)
        // A phone saved by 0.2.x: no agreed or previousKey fields.
        let old = #"{"phoneID":"p1","phoneName":"iPhone","pairKey":"\#(code.base64EncodedString())","pairedAt":0}"#
        try secrets.set(Data(old.utf8), for: "phone.p1")
        #expect(store.phoneKey(for: "p1") == PhoneKey(key: code, agreed: false))

        let phone = PairedPhone(phoneID: "p1", phoneName: "Soham's iPhone", pairKey: agreed)
        try store.saveKey(phone, PhoneKey(key: agreed, agreed: true, previous: code))
        #expect(store.phoneKey(for: "p1") == PhoneKey(key: agreed, agreed: true, previous: code))
        #expect(store.phone("p1")?.pairedAt == Date(timeIntervalSinceReferenceDate: 0))
        #expect(store.phone("p1")?.phoneName == "Soham's iPhone")
        try store.saveKey(phone, PhoneKey(key: agreed, agreed: true))
        #expect(store.phoneKey(for: "p1") == PhoneKey(key: agreed, agreed: true))
        #expect(store.storedKey(for: "p1") == agreed)

        try store.saveKey(PairedPhone(phoneID: "p2", phoneName: "New", pairKey: agreed), PhoneKey(key: agreed, agreed: true))
        #expect(store.phones.map(\.phoneID) == ["p1", "p2"])
    }

    @Test func theQuestionAndItsAnswerAreFlowPhases() {
        var flow = PairingFlow()
        let url = URL(string: "glasspad://pair?test=1")!
        flow.begin(url: url, now: Date())
        flow.approving(phoneName: "Soham's iPhone")
        #expect(flow.phase == .approving(phoneName: "Soham's iPhone"))
        #expect(flow.phase.url == nil && flow.phase.isActive)
        // The code no longer counts down while the Mac asks.
        let ranOut = flow.tick(now: Date().addingTimeInterval(PairingFlow.codeLifetime * 2))
        #expect(!ranOut)
        flow.declined(phoneName: "Soham's iPhone")
        #expect(flow.phase == .declined(phoneName: "Soham's iPhone"))
    }

    final class Answers: @unchecked Sendable {
        private let lock = NSLock()
        private var _all: [Bool] = []
        var all: [Bool] { lock.withLock { _all } }
        func add(_ a: Bool) { lock.withLock { _all.append(a) } }
    }

    @MainActor func controller() -> GlasspadController {
        GlasspadController(pairing: PairingStore(store: InMemorySecretStore()), macName: "Test Mac",
                           accessibilityCheck: { false },
                           presence: MacPresence(workspace: NotificationCenter(), distributed: NotificationCenter(),
                                                 initiallyLocked: false))
    }

    /// Cancel while the Mac asks: the server hears no at once (so the phone is refused now, not
    /// after the timeout), and the late report for that phone leaves a new code alone.
    @MainActor @Test func cancellingTheQuestionRefusesAtOnceAndKeepsTheNextCode() {
        let c = controller()
        var dismissed = 0
        c.approvalPrompt = { _, _, _ in { dismissed += 1 } }
        let answers = Answers()
        let phone = PairedPhone(phoneID: "p1", phoneName: "Phone", pairKey: Data())
        c.beginPairing()
        c.askToAllow(phone) { answers.add($0) }
        #expect(c.pairingPhase == .approving(phoneName: "Phone"))

        c.cancelPairing()
        #expect(answers.all == [false])
        #expect(dismissed == 1)
        #expect(c.pairingPhase == .idle)

        c.beginPairing()
        let armed = c.pairing.pendingKey
        #expect(armed != nil)
        // What the server reports for the refused phone arrives after the new code is up.
        c.pairingFailed(phone, .notAllowed)
        c.paired(phone)
        #expect(c.pairing.pendingKey == armed)
        #expect(c.pairingPhase.url != nil)
        #expect(answers.all == [false])
    }

    /// A second question replaces the first: the first phone is told no, and only the second
    /// phone's outcome changes the flow.
    @MainActor @Test func aSecondQuestionAnswersTheFirstNo() {
        let c = controller()
        var answerSecond: ((Bool) -> Void)?
        c.approvalPrompt = { _, _, answer in
            answerSecond = answer
            return {}
        }
        let first = Answers(), second = Answers()
        let p1 = PairedPhone(phoneID: "p1", phoneName: "One", pairKey: Data())
        let p2 = PairedPhone(phoneID: "p2", phoneName: "Two", pairKey: Data())
        c.beginPairing()
        c.askToAllow(p1) { first.add($0) }
        c.askToAllow(p2) { second.add($0) }
        #expect(first.all == [false])
        c.pairingFailed(p1, .notAllowed)
        #expect(c.pairingPhase == .approving(phoneName: "Two"))
        answerSecond?(true)
        answerSecond?(false)
        #expect(second.all == [true])
        c.paired(p2)
        #expect(c.pairingPhase == .paired(phoneName: "Two"))
    }

    /// The phone picks its own name, so the question shows it on one short line.
    @Test func phoneNamesAreMadeSafeToShow() {
        #expect(PairingFlow.displayName("Soham's iPhone") == "Soham's iPhone")
        #expect(PairingFlow.displayName("  iPhone\n\nThis Mac trusts it  ") == "iPhone This Mac trusts it")
        #expect(PairingFlow.displayName("a\u{202E}enohPi") == "a enohPi")
        #expect(PairingFlow.displayName("\n\t ") == "An iPhone")
        let long = PairingFlow.displayName(String(repeating: "x", count: 200))
        #expect(long.count == 40 && long.hasSuffix("…"))
    }

    @MainActor @Test func theCopiedLinkIsConcealedShortLivedAndCleared() {
        let pb = NSPasteboard(name: NSPasteboard.Name("glasspad-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let link = PairingLinkPasteboard(pasteboard: pb)
        let url = URL(string: "glasspad://pair?v=1&k=secret")!
        link.copy(url)
        #expect(pb.string(forType: .string) == url.absoluteString)
        #expect(pb.types?.contains(PairingLinkPasteboard.concealedType) == true)
        #expect(pb.types?.contains(PairingLinkPasteboard.transientType) == true)
        link.clear()
        #expect(pb.string(forType: .string) == nil)

        // Something copied after the link is left alone.
        link.copy(url)
        pb.clearContents()
        pb.setString("mine", forType: .string)
        link.clear()
        #expect(pb.string(forType: .string) == "mine")
    }

    @MainActor @Test func aPasswordFromAPasswordManagerIsNotSent() async {
        let pb = NSPasteboard(name: NSPasteboard.Name("glasspad-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let clip = ClipboardMode(pasteboard: pb)
        clip.accessDenied = { _ in false }
        pb.clearContents()
        pb.setString("hunter2", forType: .string)
        pb.setData(Data(), forType: ClipboardMode.concealedType)
        #expect(await clip.pullResult() == .concealed)
        #expect(clip.lastRefusal == ClipboardLimits.concealed)
        #expect(await clip.pull() == nil)
        // Plain text is sent as before.
        pb.clearContents()
        pb.setString("hello", forType: .string)
        #expect(await clip.pull() == .text("hello"))
        #expect(clip.lastRefusal == nil)
    }

    @Test func artworkIsHTTPSOnlyAndNeverLocal() async {
        let session = URLSession(configuration: .ephemeral)
        for link in ["http://i.scdn.co/image/abc", "file:///etc/passwd", "https://192.168.1.1/a.jpg",
                     "https://printer.local/a.jpg", "https://localhost/a.jpg"] {
            #expect(await MediaMode.fetchArtwork(URL(string: link)!, session: session) == nil, "\(link)")
        }
    }
}
