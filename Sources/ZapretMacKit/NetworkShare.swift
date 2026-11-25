import Darwin
import Foundation

/// S-104: sharing the SOCKS proxy with other devices on the local network.
/// tpws keeps its 127.0.0.1 bind and gets a second one on the Mac's LAN address.
public enum NetworkShare {
    /// One IPv4 address of a network interface.
    public struct Address: Equatable, Sendable {
        public var interface: String
        public var ip: String

        public init(interface: String, ip: String) {
            self.interface = interface
            self.ip = ip
        }
    }

    /// What the QR code holds: the proxy as a URL that SOCKS apps can read.
    public static func payload(ip: String, port: Int) -> String {
        "socks5://\(ip):\(port)"
    }

    /// True for an IPv4 address other devices can reach: not loopback,
    /// not link-local (169.254/16), not unspecified.
    public static func isShareable(_ ip: String) -> Bool {
        var addr = in_addr()
        guard inet_pton(AF_INET, ip, &addr) == 1 else { return false }
        let bytes = withUnsafeBytes(of: addr.s_addr) { Array($0) }
        if bytes[0] == 127 || bytes[0] == 0 { return false }
        if bytes[0] == 169 && bytes[1] == 254 { return false }
        return true
    }

    /// Picks the address to share. The interface macOS routes through
    /// (`preferred`, from the network path) wins; otherwise the first Wi-Fi or
    /// Ethernet port (en*), then any other shareable address. VPN tunnels
    /// (utun, ipsec, ppp) and bridges are skipped: devices on the LAN cannot reach them.
    public static func choose(from addresses: [Address], preferred: String?) -> Address? {
        let usable = addresses.filter { address in
            isShareable(address.ip) && !["utun", "ipsec", "ppp", "lo", "bridge", "awdl", "llw"].contains { address.interface.hasPrefix($0) }
        }
        if let preferred, let match = usable.first(where: { $0.interface == preferred }) { return match }
        return usable.first { $0.interface.hasPrefix("en") } ?? usable.first
    }

    /// Every IPv4 address of an interface that is up and running, from getifaddrs.
    public static func currentAddresses() -> [Address] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }
        var out: [Address] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let sa = entry.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            out.append(Address(interface: String(cString: entry.ifa_name), ip: ip))
        }
        return out
    }
}
