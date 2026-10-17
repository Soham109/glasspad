import Foundation

/// The keys of a cache in the order they were last used, keeping at most `limit`. The cache
/// keeps its own values; `use` says which keys fell out so it can drop them. For caches whose
/// values are large (a full-screen backdrop is about 5 MB), so that trying every theme does not
/// keep every one.
public struct RecentKeys<Key: Hashable & Sendable>: Equatable, Sendable {
    public let limit: Int
    /// Oldest first.
    public private(set) var keys: [Key] = []

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// `key` was just used. Returns the keys past the limit, oldest first (never `key`).
    @discardableResult
    public mutating func use(_ key: Key) -> [Key] {
        if keys.last == key { return [] }
        keys.removeAll { $0 == key }
        keys.append(key)
        guard keys.count > limit else { return [] }
        let dropped = Array(keys.prefix(keys.count - limit))
        keys.removeFirst(dropped.count)
        return dropped
    }

    /// Forgets every key (the cache was emptied).
    public mutating func removeAll() {
        keys.removeAll()
    }
}
