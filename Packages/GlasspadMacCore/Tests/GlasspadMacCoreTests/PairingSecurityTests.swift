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
