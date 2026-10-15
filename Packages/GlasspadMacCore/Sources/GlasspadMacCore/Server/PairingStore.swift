import Foundation
import GlasspadKit
import Security

/// A phone the Mac has paired with, as stored in the Keychain (SPEC section 3).
/// (GlasspadKit's `PairedPhone` is the transport's view; this one adds `pairedAt`.)
public struct StoredPhone: Codable, Equatable, Sendable, Identifiable {
    public var phoneID: String
    public var phoneName: String
    public var pairKey: Data
    public var pairedAt: Date
    public var id: String { phoneID }

    public init(phoneID: String, phoneName: String, pairKey: Data, pairedAt: Date = Date()) {
        self.phoneID = phoneID
        self.phoneName = phoneName
        self.pairKey = pairKey
        self.pairedAt = pairedAt
    }
}

/// Minimal secret storage so tests can run without touching the real Keychain.
public protocol SecretStore: AnyObject, Sendable {
    func data(for account: String) -> Data?
    func set(_ data: Data, for account: String) throws
    func remove(_ account: String) throws
    func accounts() -> [String]
}

public enum SecretStoreError: Error, Equatable {
    case keychain(OSStatus)
}

/// Generic-password items in the login Keychain under one service name.
public final class KeychainStore: SecretStore, @unchecked Sendable {
    public let service: String

    public init(service: String = "com.soham109.glasspad") { self.service = service }

    private func base(_ account: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    public func data(for account: String) -> Data? {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    public func set(_ data: Data, for account: String) throws {
        let status = SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = base(account)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let add = SecItemAdd(q as CFDictionary, nil)
            guard add == errSecSuccess else { throw SecretStoreError.keychain(add) }
        } else if status != errSecSuccess {
            throw SecretStoreError.keychain(status)
        }
    }

    public func remove(_ account: String) throws {
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
    }

    public func accounts() -> [String] {
        var q = base()
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func data(for account: String) -> Data? { lock.withLock { items[account] } }
    public func set(_ data: Data, for account: String) throws { lock.withLock { items[account] = data } }
    public func remove(_ account: String) throws { _ = lock.withLock { items.removeValue(forKey: account) } }
    public func accounts() -> [String] { lock.withLock { Array(items.keys) } }
}

/// macID, paired phones and the one pending pairing key shown in the QR code.
/// Thread safe: the transport calls `storedKey(for:)` from its own queue.
public final class PairingStore: @unchecked Sendable {
    static let macIDAccount = "macID"
    static let phonePrefix = "phone."

    private let store: SecretStore
    private let lock = NSLock()
    private var _pendingKey: Data?
    public let macID: UUID
    public var pendingKey: Data? { lock.withLock { _pendingKey } }

    public init(store: SecretStore = KeychainStore()) {
        self.store = store
        if let d = store.data(for: Self.macIDAccount), let s = String(data: d, encoding: .utf8), let id = UUID(uuidString: s) {
            macID = id
        } else {
            let id = UUID()
            try? store.set(Data(id.uuidString.utf8), for: Self.macIDAccount)
            macID = id
        }
    }

    public var phones: [StoredPhone] {
        store.accounts()
            .filter { $0.hasPrefix(Self.phonePrefix) }
            .compactMap { store.data(for: $0) }
            .compactMap { try? JSONDecoder().decode(StoredPhone.self, from: $0) }
            .sorted { $0.pairedAt < $1.pairedAt }
    }

    public func phone(_ phoneID: String) -> StoredPhone? {
        store.data(for: Self.phonePrefix + phoneID).flatMap { try? JSONDecoder().decode(StoredPhone.self, from: $0) }
    }

    /// Creates a fresh pending key and returns the payload to encode as a QR code.
    public func beginPairing(macName: String) -> PairingPayload {
        let key = PairingPayload.generateKey()
        lock.withLock { _pendingKey = key }
        return PairingPayload(macID: macID, macName: macName, pairKey: key)
    }

    public func cancelPairing() { lock.withLock { _pendingKey = nil } }

    /// Key to use for a phone that says hello: its stored key, else the pending key.
    public func key(for phoneID: String) -> Data? {
        storedKey(for: phoneID) ?? pendingKey
    }

    /// Stored key only (the transport handles the pending key itself).
    public func storedKey(for phoneID: String) -> Data? { phone(phoneID)?.pairKey }

    /// Saves a phone the transport just paired (GlasspadServer.onPaired) and clears the pending key.
    @discardableResult
    public func save(phoneID: String, phoneName: String, pairKey: Data) throws -> StoredPhone {
        let phone = StoredPhone(phoneID: phoneID, phoneName: phoneName, pairKey: pairKey)
        try store.set(try JSONEncoder().encode(phone), for: Self.phonePrefix + phoneID)
        lock.withLock { if _pendingKey == pairKey { _pendingKey = nil } }
        return phone
    }

    /// Called once a new phone proved it holds the pending key. Consumes the pending key.
    @discardableResult
    public func completePairing(phoneID: String, phoneName: String) throws -> StoredPhone? {
        guard let key = pendingKey else { return nil }
        return try save(phoneID: phoneID, phoneName: phoneName, pairKey: key)
    }

    public func revoke(_ phoneID: String) throws {
        try store.remove(Self.phonePrefix + phoneID)
    }
}
