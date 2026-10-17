import Foundation
import Security

/// One Mac the phone has paired with.
public struct KnownMac: Codable, Equatable, Sendable, Identifiable {
    public var pairing: PairingPayload
    public var pairedAt: Date
    /// Last time a session with this Mac reached `connected`.
    public var lastConnectedAt: Date?
    /// From the Mac's last handshake; nil until the first connect (or for a Mac on loopback).
    public var wakeTarget: WakeTarget?
    /// True once `pairing.pairKey` is a key agreed with the Mac (protocol 2), not the one from the
    /// pairing code. nil (every Mac paired by 0.2.x and earlier, and a fresh scan) means a code's
    /// key, which the next protocol 2 connection replaces.
    public var keyAgreed: Bool?

    public var id: UUID { pairing.macID }
    public var name: String { pairing.macName }

    public init(pairing: PairingPayload, pairedAt: Date = Date(), lastConnectedAt: Date? = nil, wakeTarget: WakeTarget? = nil) {
        self.pairing = pairing
        self.pairedAt = pairedAt
        self.lastConnectedAt = lastConnectedAt
        self.wakeTarget = wakeTarget
    }
}

/// The phone's list of paired Macs, and which one it used last. A plain value; `KnownMacsStore`
/// persists it.
public struct KnownMacs: Codable, Equatable, Sendable {
    public private(set) var macs: [KnownMac]
    /// The Mac chosen or connected most recently.
    public private(set) var lastUsedID: UUID?

    public init(macs: [KnownMac] = [], lastUsedID: UUID? = nil) {
        self.macs = macs
        self.lastUsedID = lastUsedID
    }

    public subscript(id: UUID) -> KnownMac? { macs.first { $0.id == id } }

    /// Adds a Mac from a scanned QR code. Scanning a Mac again replaces its key and name (the
    /// Mac made a new pairing) and keeps its history. The new pairing becomes the last used Mac.
    @discardableResult
    public mutating func add(_ pairing: PairingPayload, at date: Date = Date()) -> KnownMac {
        var mac = KnownMac(pairing: pairing, pairedAt: date)
        if let i = macs.firstIndex(where: { $0.id == pairing.macID }) {
            mac.lastConnectedAt = macs[i].lastConnectedAt
            mac.wakeTarget = macs[i].wakeTarget
            macs[i] = mac
        } else {
            macs.append(mac)
        }
        lastUsedID = pairing.macID
        return mac
    }

    public mutating func remove(_ id: UUID) {
        macs.removeAll { $0.id == id }
        if lastUsedID == id { lastUsedID = mostRecent?.id }
    }

    /// The user picked this Mac.
    public mutating func select(_ id: UUID) {
        guard self[id] != nil else { return }
        lastUsedID = id
    }

    /// A session with this Mac reached `connected`.
    public mutating func markConnected(_ id: UUID, at date: Date = Date()) {
        guard let i = macs.firstIndex(where: { $0.id == id }) else { return }
        macs[i].lastConnectedAt = date
        lastUsedID = id
    }

    /// The Mac and this phone agreed a new pair key: it replaces the code's key for good.
    public mutating func setAgreedKey(_ key: Data, for id: UUID) {
        guard let i = macs.firstIndex(where: { $0.id == id }) else { return }
        macs[i].pairing.pairKey = key
        macs[i].keyAgreed = true
    }

    public mutating func setWakeTarget(_ target: WakeTarget?, for id: UUID) {
        guard let i = macs.firstIndex(where: { $0.id == id }) else { return }
        macs[i].wakeTarget = target
    }

    /// The Mac to connect to on launch: the last used one, else the most recently connected or
    /// paired. nil when nothing is paired.
    public var lastUsed: KnownMac? {
        if let id = lastUsedID, let m = self[id] { return m }
        return mostRecent
    }

    /// Most recent first (connected, else paired).
    public var byRecency: [KnownMac] {
        macs.sorted { ($0.lastConnectedAt ?? $0.pairedAt) > ($1.lastConnectedAt ?? $1.pairedAt) }
    }

    private var mostRecent: KnownMac? { byRecency.first }
}

/// Where `KnownMacsStore` keeps its bytes.
public protocol KnownMacsStorage: Sendable {
    func load() -> Data?
    func save(_ data: Data) throws
}

/// One generic-password Keychain item (pair keys are secrets). Works on iOS and macOS.
public struct KeychainKnownMacsStorage: KnownMacsStorage {
    public let service: String
    public let account: String

    public init(service: String = "com.soham109.glasspad.macs", account: String = "knownMacs") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    public func save(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let add = SecItemAdd(q as CFDictionary, nil)
            guard add == errSecSuccess else { throw KnownMacsStoreError.keychain(add) }
        } else if status != errSecSuccess {
            throw KnownMacsStoreError.keychain(status)
        }
    }
}

/// Keeps bytes in memory (tests and previews).
public final class InMemoryKnownMacsStorage: KnownMacsStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    public init(_ data: Data? = nil) { self.data = data }
    public func load() -> Data? { lock.withLock { data } }
    public func save(_ d: Data) throws { lock.withLock { data = d } }
}

public enum KnownMacsStoreError: Error, Equatable {
    case keychain(OSStatus)
}

/// Thread-safe, persisted `KnownMacs`. Every change is saved at once.
public final class KnownMacsStore: @unchecked Sendable {
    private let storage: any KnownMacsStorage
    private let lock = NSLock()
    private var value: KnownMacs

    public init(storage: any KnownMacsStorage = KeychainKnownMacsStorage()) {
        self.storage = storage
        if let d = storage.load(), let v = try? JSONDecoder().decode(KnownMacs.self, from: d) {
            value = v
        } else {
            value = KnownMacs()
        }
    }

    public var current: KnownMacs { lock.withLock { value } }

    /// Applies a change and saves it. Returns the closure's result. The save happens under the
    /// lock so saves land in the same order as the changes (otherwise a slower save of an older
    /// state could overwrite a newer one).
    /// Like `update`, and says whether the change reached storage (a pair key that did not
    /// must not be reported as saved).
    public func updateAndSave(_ change: (inout KnownMacs) -> Void) -> Bool {
        lock.withLock {
            change(&value)
            guard let d = try? JSONEncoder().encode(value) else { return false }
            return (try? storage.save(d)) != nil
        }
    }

    @discardableResult
    public func update<R>(_ change: (inout KnownMacs) -> R) -> R {
        lock.withLock {
            let r = change(&value)
            if let d = try? JSONEncoder().encode(value) { try? storage.save(d) }
            return r
        }
    }
}
