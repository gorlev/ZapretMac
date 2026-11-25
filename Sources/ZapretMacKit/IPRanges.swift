import Darwin
import Foundation

/// What a site list holds: domain names (tpws `--hostlist`) or IP
/// addresses and ranges (tpws `--ipset`).
public enum ListKind: String, CaseIterable, Sendable, Codable {
    case domains, addresses
}

/// Cleans IP addresses and ranges people paste or subscribe to, in the
/// format tpws's `--ipset` files use: one address or CIDR range per line,
/// IPv4 and IPv6.
public enum IPRanges {
    /// "10.1.2.3/8" -> "10.0.0.0/8", "2001:DB8::1" -> "2001:db8::1",
    /// "1.2.3.4/32" -> "1.2.3.4". Nil for text that is not an address or range.
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]).trimmingCharacters(in: .whitespaces) }
        guard !s.isEmpty, s.count <= 64 else { return nil }
        var prefix: Int?
        if let slash = s.firstIndex(of: "/") {
            let digits = s[s.index(after: slash)...]
            guard (1...3).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let n = Int(digits) else { return nil }
            prefix = n
            s = String(s[..<slash])
        }
        if s.hasPrefix("["), s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        let v6 = s.contains(":")
        let family = v6 ? AF_INET6 : AF_INET
        let width = v6 ? 128 : 32
        var bytes = [UInt8](repeating: 0, count: width / 8)
        guard s.allSatisfy({ $0.isASCII && ($0.isHexDigit || $0 == "." || $0 == ":") }),
              inet_pton(family, s, &bytes) == 1 else { return nil }
        let bits = prefix ?? width
        guard bits <= width else { return nil }
        // The network address: host bits cleared, as tpws reads the range.
        for i in bytes.indices {
            let keep = max(0, min(8, bits - i * 8))
            bytes[i] &= keep == 0 ? 0 : UInt8(truncatingIfNeeded: 0xFF << (8 - keep))
        }
        var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(family, bytes, &text, socklen_t(text.count)) != nil else { return nil }
        let address = String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return bits == width ? address : "\(address)/\(bits)"
    }

    public static func isAddress(_ raw: String) -> Bool { normalize(raw) != nil }

    /// Splits pasted text or a file like `Domains.parseList`, keeps the
    /// addresses and ranges, normalized, each once, in order.
    public static func parseList(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for piece in Domains.pieces(text) {
            if let range = normalize(piece), seen.insert(range).inserted { out.append(range) }
        }
        return out
    }

    /// Sorts pasted text into domains and addresses. A piece that reads as an
    /// address is an address ("1.2.3.4" is never a domain); the rest are
    /// domains when they look like one. Each once, in order.
    public static func route(_ text: String) -> (domains: [String], addresses: [String]) {
        var seen = Set<String>()
        var domains: [String] = []
        var addresses: [String] = []
        for piece in Domains.pieces(text) {
            if let range = normalize(piece) {
                if seen.insert(range).inserted { addresses.append(range) }
            } else if let domain = Domains.normalize(piece), seen.insert(domain).inserted {
                domains.append(domain)
            }
        }
        return (domains, addresses)
    }
}
