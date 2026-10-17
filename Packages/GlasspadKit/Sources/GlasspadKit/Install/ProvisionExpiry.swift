import Foundation

/// When an install made with a free Apple account stops opening: the `ExpirationDate` of the
/// provisioning profile Xcode embeds in the app (`embedded.mobileprovision`).
///
/// The profile is a signed envelope around a property list. The signature needs no checking
/// here (iOS checked it to launch the app), so the plist is read straight out of the bytes.
public enum ProvisionExpiry {
    public static func expirationDate(fromProvision data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.upperBound..<data.endIndex) else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] else {
            return nil
        }
        return object["ExpirationDate"] as? Date
    }
}
