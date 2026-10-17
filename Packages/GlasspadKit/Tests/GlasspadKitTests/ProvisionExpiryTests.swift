import Foundation
import Testing
@testable import GlasspadKit

// The iPhone's "Works Until" date, read out of the profile Xcode embeds in the app.

@Suite struct ProvisionExpiryTests {
    /// A profile as Xcode writes one: signature bytes, the plist, more signature bytes.
    private func profile(_ plist: String) -> Data {
        var data = Data([0x30, 0x80, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0, 0x80, 0x00, 0x3C])
        data.append(Data(plist.utf8))
        data.append(Data([0x00, 0x00, 0xA0, 0x82, 0x3C, 0x2F, 0xFF, 0x00]))
        return data
    }

    private func plist(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(body)
        </dict>
        </plist>
        """
    }

    @Test func readsTheExpirationDate() {
        let body = """
            <key>AppIDName</key><string>Glasspad</string>
            <key>CreationDate</key><date>2026-10-16T09:00:00Z</date>
            <key>ExpirationDate</key><date>2026-10-23T09:00:00Z</date>
            <key>Entitlements</key><dict><key>get-task-allow</key><true/></dict>
            """
        let date = ProvisionExpiry.expirationDate(fromProvision: profile(plist(body)))
        #expect(date == ISO8601DateFormatter().date(from: "2026-10-23T09:00:00Z"))
    }

    @Test func nothingUsable() {
        #expect(ProvisionExpiry.expirationDate(fromProvision: Data()) == nil)
        #expect(ProvisionExpiry.expirationDate(fromProvision: Data((0..<512).map { UInt8($0 & 0xFF) })) == nil)
        // No plist end, a broken plist, no ExpirationDate, or one that is not a date.
        #expect(ProvisionExpiry.expirationDate(fromProvision: profile("<?xml version=\"1.0\"?><plist><dict>")) == nil)
        #expect(ProvisionExpiry.expirationDate(fromProvision: profile("<?xml version=\"1.0\"?><plist><dict><key>Ex</plist>")) == nil)
        #expect(ProvisionExpiry.expirationDate(fromProvision: profile(plist("<key>Name</key><string>x</string>"))) == nil)
        #expect(ProvisionExpiry.expirationDate(fromProvision: profile(plist("<key>ExpirationDate</key><string>soon</string>"))) == nil)
    }
}
