import Foundation

// Decoding that survives a newer build's additions inside a list, so one thing this build
// cannot read costs that one thing, not the whole message.

/// Any JSON value, kept as it came so it can be written back unchanged.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// One list element, or nil when it cannot be read. Always consumes the element, so the rest
/// of the list still decodes.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    /// The list under `key`, skipping only the elements that cannot be read.
    func decodeLenientArray<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        try decode([Lenient<T>].self, forKey: key).compactMap(\.value)
    }

    func decodeLenientArrayIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T]? {
        try decodeIfPresent([Lenient<T>].self, forKey: key)?.compactMap(\.value)
    }
}
