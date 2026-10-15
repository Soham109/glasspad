import Foundation
import Observation
import Security
import GlasspadKit

/// One Mac this phone has paired with, as the views see it. The key never leaves the
/// Keychain except to derive session keys in memory.
struct PairedMac: Codable, Identifiable, Equatable, Sendable {
    var macID: UUID
    var name: String
    var pairKey: Data
    var pairedAt: Date
    /// How to wake this Mac, from its last handshake. nil until the first connect.
    var wakeTarget: WakeTarget?

    var id: UUID { macID }

    var payload: PairingPayload { PairingPayload(macID: macID, macName: name, pairKey: pairKey) }

    init(macID: UUID, name: String, pairKey: Data, pairedAt: Date, wakeTarget: WakeTarget? = nil) {
        self.macID = macID
        self.name = name
        self.pairKey = pairKey
        self.pairedAt = pairedAt
        self.wakeTarget = wakeTarget
    }

    init(_ known: KnownMac) {
        self.init(macID: known.id, name: known.name, pairKey: known.pairing.pairKey,
                  pairedAt: known.pairedAt, wakeTarget: known.wakeTarget)
    }
}

/// Paired Macs, kept by GlasspadKit's `KnownMacsStore` in one this-device-only Keychain item
/// (never synced to iCloud, readable after first unlock so Siri and Shortcuts work while
/// locked). `MacConnector` reads and updates the same store; `reload()` picks that up.
@MainActor
@Observable
final class PairingStore {
    static let shared = PairingStore()

    /// Most recently paired first.
    private(set) var macs: [PairedMac] = []
    /// The Mac the app connects to: the last one chosen or connected.
    private(set) var selectedID: UUID?

    var selected: PairedMac? {
        macs.first { $0.macID == selectedID } ?? macs.first
    }

    /// Shared with `MacConnector`.
    @ObservationIgnored let known: KnownMacsStore

    /// A stable random identifier for this phone, created once and kept in the Keychain.
    let phoneID: UUID

    private static let service = "com.soham109.glasspad.pairing"
    private static let phoneIDAccount = "phone-id"
    private static let selectedKey = "selectedMac"

    init() {
        phoneID = Self.loadOrCreatePhoneID()
        known = KnownMacsStore()
        migrateFromOneItemPerMac()
        reload()
    }

    /// Re-reads the shared store (after the connector marked a connect or saved a wake target).
    func reload() {
        let current = known.current
        let list = current.macs.map(PairedMac.init).sorted { $0.pairedAt > $1.pairedAt }
        if list != macs { macs = list }
        let id = current.lastUsed?.id
        if id != selectedID { selectedID = id }
    }

    /// Saves a newly scanned Mac (replacing an earlier pairing with the same Mac) and selects it.
    @discardableResult
    func add(_ payload: PairingPayload) -> PairedMac {
        let mac = known.update { $0.add(payload) }
        reload()
        return PairedMac(mac)
    }

    func select(_ id: UUID) {
        known.update { $0.select(id) }
        reload()
    }

    func forget(_ mac: PairedMac) {
        known.update { $0.remove(mac.macID) }
        reload()
    }

    func setWakeTarget(_ target: WakeTarget, for id: UUID) {
        known.update { $0.setWakeTarget(target, for: id) }
        reload()
    }

    /// Builds before the shared store kept one Keychain item per Mac. Moves them over once,
    /// keeping the chosen Mac, then deletes the old items. The phone id stays where it is.
    private func migrateFromOneItemPerMac() {
        let old = Self.loadAll()
        guard !old.isEmpty else { return }
        let chosen = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:))
        known.update { macs in
            for mac in old.sorted(by: { $0.pairedAt < $1.pairedAt }) where macs[mac.macID] == nil {
                macs.add(mac.payload, at: mac.pairedAt)
            }
            if let chosen { macs.select(chosen) }
        }
        guard known.current.macs.count >= old.count else { return }
        for mac in old { Self.delete(account: mac.macID.uuidString) }
        UserDefaults.standard.removeObject(forKey: Self.selectedKey)
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
