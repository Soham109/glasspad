import Foundation
import CoreGraphics

public enum TouchCodecError: Error, Equatable, Sendable {
    case tooShort
    case unknownKind(UInt8)
    case tooManyTouches(Int)
    case lengthMismatch(expected: Int, actual: Int)
    case badPhase(UInt8)
    case emptySurface
    case duplicateTouchID(UInt8)
    /// `decode` was given a heartbeat; use `decodePacket` to accept both.
    case notTouchPacket
}

/// A decoded UDP packet.
public enum TouchPacket: Equatable, Sendable {
    case touches(TouchFrame)
    case heartbeat(seq: UInt32, timestamp: TimeInterval)
}

/// Compact little-endian binary format for the UDP touch link (SPEC section 5).
///
/// Header (18 bytes): u8 kind, u32 seq, u64 tPhoneMicros, u8 count,
/// u16 surfaceWidthPt, u16 surfaceHeightPt. Then `count` touches of 8 bytes:
/// u8 id, u8 phase, u16 x, u16 y, u8 majorRadius (points / 2), u8 reserved.
public enum TouchCodec {
    public static let headerSize = 18
    public static let touchSize = 8
    public static let maxTouches = 10
    static let kindTouches: UInt8 = 1
    static let kindHeartbeat: UInt8 = 2

    public static func encode(_ frame: TouchFrame) -> Data {
        let touches = frame.touches.prefix(maxTouches)
        let w = Double(clampU16(frame.surface.width))
        let h = Double(clampU16(frame.surface.height))
        var out = Data(capacity: headerSize + touchSize * touches.count)
        out.append(kindTouches)
        appendLE(&out, frame.seq)
        appendLE(&out, micros(frame.timestamp))
        out.append(UInt8(touches.count))
        appendLE(&out, UInt16(w))
        appendLE(&out, UInt16(h))
        for t in touches {
            out.append(t.id)
            out.append(t.phase.rawValue)
            appendLE(&out, quantize(t.x, over: w))
            appendLE(&out, quantize(t.y, over: h))
            let r = (t.majorRadius / 2).rounded()
            out.append(UInt8(r.isFinite ? min(max(r, 0), 255) : 0))
            out.append(0)
        }
        return out
    }

    public static func heartbeat(seq: UInt32, timestamp: TimeInterval = 0) -> Data {
        var out = Data(capacity: headerSize)
        out.append(kindHeartbeat)
        appendLE(&out, seq)
        appendLE(&out, micros(timestamp))
        out.append(0)
        appendLE(&out, UInt16(0))
        appendLE(&out, UInt16(0))
        return out
    }

    /// Decodes a touches packet. Throws `.notTouchPacket` for a heartbeat.
    public static func decode(_ data: Data) throws -> TouchFrame {
        switch try decodePacket(data) {
        case .touches(let f): return f
        case .heartbeat: throw TouchCodecError.notTouchPacket
        }
    }

    /// Decodes either packet kind, validating every field.
    public static func decodePacket(_ data: Data) throws -> TouchPacket {
        let b = [UInt8](data)
        guard b.count >= headerSize else { throw TouchCodecError.tooShort }
        let kind = b[0]
        let seq = UInt32(readLE(b, 1, 4))
        let t = TimeInterval(readLE(b, 5, 8)) / 1_000_000
        let count = Int(b[13])
        let w = Double(readLE(b, 14, 2))
        let h = Double(readLE(b, 16, 2))
        switch kind {
        case kindHeartbeat:
            guard b.count == headerSize else {
                throw TouchCodecError.lengthMismatch(expected: headerSize, actual: b.count)
            }
            return .heartbeat(seq: seq, timestamp: t)
        case kindTouches:
            break
        default:
            throw TouchCodecError.unknownKind(kind)
        }
        guard count <= maxTouches else { throw TouchCodecError.tooManyTouches(count) }
        let expected = headerSize + touchSize * count
        guard b.count == expected else {
            throw TouchCodecError.lengthMismatch(expected: expected, actual: b.count)
        }
        guard w > 0, h > 0 else { throw TouchCodecError.emptySurface }
        var touches: [Touch] = []
        touches.reserveCapacity(count)
        var seen = Set<UInt8>()
        for i in 0..<count {
            let o = headerSize + i * touchSize
            let id = b[o]
            guard let phase = TouchPhase(rawValue: b[o + 1]) else { throw TouchCodecError.badPhase(b[o + 1]) }
            guard seen.insert(id).inserted else { throw TouchCodecError.duplicateTouchID(id) }
            let x = Double(readLE(b, o + 2, 2)) / 65535 * w
            let y = Double(readLE(b, o + 4, 2)) / 65535 * h
            touches.append(Touch(id: id, phase: phase, x: x, y: y, majorRadius: Double(b[o + 6]) * 2))
        }
        return .touches(TouchFrame(seq: seq, timestamp: t, touches: touches, surface: CGSize(width: w, height: h)))
    }

    // MARK: helpers

    private static func micros(_ t: TimeInterval) -> UInt64 {
        guard t.isFinite, t > 0 else { return 0 }
        let m = (t * 1_000_000).rounded()
        return m >= 1.8e19 ? UInt64.max : UInt64(m)
    }

    private static func clampU16(_ v: CGFloat) -> UInt16 {
        let d = Double(v).rounded()
        guard d.isFinite else { return 1 }
        return UInt16(min(max(d, 1), 65535))
    }

    private static func quantize(_ v: Double, over size: Double) -> UInt16 {
        guard v.isFinite, size > 0 else { return 0 }
        let f = min(max(v / size, 0), 1)
        return UInt16((f * 65535).rounded())
    }

    private static func appendLE<T: FixedWidthInteger>(_ d: inout Data, _ v: T) {
        withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
    }

    private static func readLE(_ b: [UInt8], _ at: Int, _ n: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<n { v |= UInt64(b[at + i]) << (8 * UInt64(i)) }
        return v
    }
}
