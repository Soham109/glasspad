import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Where to send a Wake-on-LAN magic packet for one Mac. The Mac sends this to the phone after
/// every successful handshake (sealed, inside the transport), so the phone always has the
/// address of the interface it last reached the Mac on.
public struct WakeTarget: Codable, Equatable, Hashable, Sendable {
    /// Hardware address, lowercase `aa:bb:cc:dd:ee:ff`.
    public var macAddress: String
    /// IPv4 broadcast address of the Mac's subnet, e.g. `192.168.1.255`.
    public var broadcastAddress: String
    /// The Mac's IPv4 address on that subnet (a unicast copy helps when broadcast is filtered).
    public var lastIPv4: String?
    /// UDP port for the magic packet. 9 (discard) is the convention.
    public var port: UInt16

    public init(macAddress: String, broadcastAddress: String, lastIPv4: String? = nil, port: UInt16 = 9) {
        self.macAddress = macAddress
        self.broadcastAddress = broadcastAddress
        self.lastIPv4 = lastIPv4
        self.port = port
    }
}

public enum WakeOnLANError: Error, Equatable, Sendable {
    case badMACAddress(String)
    case socket(Int32)
    case badAddress(String)
    case sendFailed(Int32)
}

/// Wake-on-LAN: the magic packet is 6 bytes of 0xFF followed by the 6-byte hardware address
/// 16 times (102 bytes), sent as a UDP broadcast.
///
/// The Mac wakes for it when System Settings > Battery (or Energy) > "Wake for network access"
/// is on. On iPhone, sending a broadcast needs the `com.apple.developer.networking.multicast`
/// entitlement; without it `send` throws `sendFailed` and only the unicast copy may go out.
public enum WakeOnLAN {
    public static let packetLength = 102

    /// Parses `aa:bb:cc:dd:ee:ff` or `aa-bb-cc-dd-ee-ff` (any case).
    public static func parseMAC(_ s: String) -> [UInt8]? {
        let parts = s.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        var out: [UInt8] = []
        for p in parts {
            guard p.count == 2, let b = UInt8(p, radix: 16) else { return nil }
            out.append(b)
        }
        return out
    }

    public static func formatMAC(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// The 102-byte magic packet, nil for a malformed address.
    public static func magicPacket(macAddress: String) -> Data? {
        guard let mac = parseMAC(macAddress), mac != [0, 0, 0, 0, 0, 0] else { return nil }
        var d = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { d.append(contentsOf: mac) }
        return d
    }

    /// Sends the magic packet to the subnet broadcast address, to 255.255.255.255, and to the
    /// Mac's last unicast address. Succeeds when at least one copy left the phone.
    /// Returns the destinations that were sent to.
    @discardableResult
    public static func send(to target: WakeTarget) throws -> [String] {
        guard let packet = magicPacket(macAddress: target.macAddress) else {
            throw WakeOnLANError.badMACAddress(target.macAddress)
        }
        var hosts = [target.broadcastAddress, "255.255.255.255"]
        if let ip = target.lastIPv4 { hosts.append(ip) }
        var sent: [String] = []
        var lastError: Error?
        for h in hosts {
            do {
                try sendDatagram(packet, toIPv4: h, port: target.port)
                sent.append(h)
            } catch {
                lastError = error
            }
        }
        if sent.isEmpty, let lastError { throw lastError }
        return sent
    }

    /// One UDP datagram over a BSD socket with SO_BROADCAST set.
    static func sendDatagram(_ data: Data, toIPv4 host: String, port: UInt16) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw WakeOnLANError.socket(errno) }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { throw WakeOnLANError.badAddress(host) }
        let n = data.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard n == data.count else { throw WakeOnLANError.sendFailed(errno) }
    }

    // MARK: Finding the local interface (Mac side)

    /// One network interface as reported by `getifaddrs`.
    public struct Interface: Equatable, Sendable {
        public var name: String
        public var macAddress: String?
        public var ipv4: [String]
        public var ipv6: [String]
        public var broadcast: String?
    }

    public static func interfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var byName: [String: Interface] = [:]
        var order: [String] = []
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            defer { p = cur.pointee.ifa_next }
            guard let sa = cur.pointee.ifa_addr else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            if byName[name] == nil {
                byName[name] = Interface(name: name, macAddress: nil, ipv4: [], ipv6: [], broadcast: nil)
                order.append(name)
            }
            switch Int32(sa.pointee.sa_family) {
            case AF_LINK:
                sa.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl in
                    let nlen = Int(dl.pointee.sdl_nlen), alen = Int(dl.pointee.sdl_alen)
                    guard alen == 6, let offset = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) else { return }
                    // sdl_data is declared as 12 bytes, but the kernel sizes the struct to hold the
                    // interface name followed by the address, so read through the raw pointer.
                    let base = UnsafeRawPointer(dl).advanced(by: offset + nlen)
                    let bytes = (0..<alen).map { base.load(fromByteOffset: $0, as: UInt8.self) }
                    if bytes != [0, 0, 0, 0, 0, 0] { byName[name]?.macAddress = formatMAC(bytes) }
                }
            case AF_INET:
                if let ip = numericHost(sa) { byName[name]?.ipv4.append(ip) }
                let flags = Int32(cur.pointee.ifa_flags)
                if flags & IFF_BROADCAST != 0, let b = cur.pointee.ifa_dstaddr, let bs = numericHost(b) {
                    byName[name]?.broadcast = bs
                }
            case AF_INET6:
                if let ip = numericHost(sa) { byName[name]?.ipv6.append(ip) }
            default:
                break
            }
        }
        return order.compactMap { byName[$0] }
    }

    /// The wake target for the interface that owns `localAddress` (the Mac's end of the phone's
    /// TCP connection, IPv4 or IPv6). nil for loopback or an interface without a hardware address
    /// or IPv4 broadcast address.
    public static func target(forLocalAddress localAddress: String, in list: [Interface] = interfaces()) -> WakeTarget? {
        let wanted = stripZone(localAddress).lowercased()
        guard let iface = list.first(where: { i in
            i.ipv4.contains(wanted) || i.ipv6.contains { stripZone($0).lowercased() == wanted }
        }), let mac = iface.macAddress, let broadcast = iface.broadcast else { return nil }
        return WakeTarget(macAddress: mac, broadcastAddress: broadcast, lastIPv4: iface.ipv4.first)
    }

    static func stripZone(_ s: String) -> String {
        s.split(separator: "%", maxSplits: 1).first.map(String.init) ?? s
    }

    private static func numericHost(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let len = socklen_t(sa.pointee.sa_len)
        guard getnameinfo(sa, len, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return buf.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}
