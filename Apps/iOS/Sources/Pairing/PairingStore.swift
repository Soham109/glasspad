import Foundation
import Observation
import Security
import GlasspadKit

/// One Mac this phone has paired with. The key never leaves the Keychain except to
/// derive session keys in memory.
struct PairedMac: Codable, Identifiable, Equatable, Sendable {
    var macID: UUID
    var name: String
    var pairKey: Data
    var pairedAt: Date

    var id: UUID { macID }

    var payload: PairingPayload { PairingPayload(macID: macID, macName: name, pairKey: pairKey) }
}

/// Paired Macs in the iOS Keychain. Items are this-device-only (never synced to iCloud)
/// and readable after first unlock, so Siri and Shortcuts actions work while locked.
@MainActor
@Observable
final class PairingStore {
    static let shared = PairingStore()

    private(set) var macs: [PairedMac] = []
    /// The Mac the app connects to. Falls back to the most recently paired one.
    var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey) }
    }

    var selected: PairedMac? {
        macs.first { $0.macID == selectedID } ?? macs.first
    }

    /// A stable random identifier for this phone, created once and kept in the Keychain.
    let phoneID: UUID

    private static let service = "com.soham109.glasspad.pairing"
    private static let phoneIDAccount = "phone-id"
    private static let selectedKey = "selectedMac"

    init() {
        phoneID = Self.loadOrCreatePhoneID()
        macs = Self.loadAll().sorted { $0.pairedAt > $1.pairedAt }
        if let raw = UserDefaults.standard.string(forKey: Self.selectedKey) {
            selectedID = UUID(uuidString: raw)
        }
    }

    /// Saves a newly scanned Mac (replacing an earlier pairing with the same Mac) and selects it.
    @discardableResult
    func add(_ payload: PairingPayload) -> PairedMac {
        let mac = PairedMac(macID: payload.macID, name: payload.macName, pairKey: payload.pairKey, pairedAt: .now)
        if let data = try? JSONEncoder().encode(mac) {
            Self.write(account: mac.macID.uuidString, data: data)
        }
        macs.removeAll { $0.macID == mac.macID }
        macs.insert(mac, at: 0)
        selectedID = mac.macID
        return mac
    }

    func forget(_ mac: PairedMac) {
        Self.delete(account: mac.macID.uuidString)
        macs.removeAll { $0.macID == mac.macID }
        if selectedID == mac.macID { selectedID = macs.first?.macID }
    }

    // MARK: Keychain

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func write(account: String, data: Data) {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    private static func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func loadAll() -> [PairedMac] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard (item[kSecAttrAccount as String] as? String) != phoneIDAccount,
                  let data = item[kSecValueData as String] as? Data else { return nil }
            return try? JSONDecoder().decode(PairedMac.self, from: data)
        }
    }

    private static func loadOrCreatePhoneID() -> UUID {
        if let data = read(account: phoneIDAccount),
           let text = String(data: data, encoding: .utf8),
           let id = UUID(uuidString: text) {
            return id
        }
        let id = UUID()
        write(account: phoneIDAccount, data: Data(id.uuidString.utf8))
        return id
    }
}
