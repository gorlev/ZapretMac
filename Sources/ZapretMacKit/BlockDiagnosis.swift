import Foundation

/// What the system resolver's answer looks like next to DNS-over-HTTPS
/// answers from public resolvers (zapret blockcheck's `check_dns_spoof`).
public enum DNSVerdict: Equatable, Sendable {
    /// The system answer shares an address with the public answers.
    case agrees
    /// The provider answers differently, or not at all, while the public resolvers agree.
    case spoofed
    /// Nothing to compare: the public resolvers gave no usable answer or disagree.
    case unknown
}

/// The kind of block one site has, from the short diagnosis before a scan.
public enum BlockKind: String, Equatable, Sendable, CaseIterable {
    /// The provider changes the site's DNS answers.
    case dns
    /// The site's address itself is blocked.
    case ip
    /// The filter reads the site name (DPI); a strategy can help.
    case dpi
    /// The site opens without help.
    case none

    /// One sentence for the verdict line.
    public var message: String {
        switch self {
        case .dns: String(localized: "Your provider changes this site's DNS answers. Turn on encrypted DNS (DNS over HTTPS) for this to work.", bundle: .main)
        case .ip: String(localized: "This site's address is blocked. ZapretMac cannot get around that.", bundle: .main)
        case .dpi: String(localized: "The filter reads the site name. A strategy can get around this.", bundle: .main)
        case .none: String(localized: "No block found: the site opens without ZapretMac.", bundle: .main)
        }
    }

    /// An SF Symbol for the verdict line.
    public var symbol: String {
        switch self {
        case .dns: "exclamationmark.triangle.fill"
        case .ip: "nosign"
        case .dpi: "checkmark.shield.fill"
        case .none: "checkmark.circle.fill"
        }
    }

    /// Whether a strategy can make the site open.
    public var strategyCanHelp: Bool { self == .dpi }
}

public enum BlockDiagnosis {
    /// Compares the system resolver's addresses (nil: no answer) with the
    /// IPv4 answers of several DoH resolvers (nil: that resolver failed).
    /// Only IPv4 addresses are compared, since DoH is asked for A records.
    public static func dnsVerdict(system: [String]?, doh: [[String]?]) -> DNSVerdict {
        let publicAnswers = doh.compactMap { $0.map { Set($0.filter(isIPv4)) } }.filter { !$0.isEmpty }
        guard !publicAnswers.isEmpty else { return .unknown }
        let systemAll = system ?? []
        let systemV4 = Set(systemAll.filter(isIPv4))
        // An IPv6-only system answer cannot be compared with A records.
        if systemV4.isEmpty && !systemAll.isEmpty { return .unknown }
        let union = publicAnswers.reduce(into: Set<String>()) { $0.formUnion($1) }
        // A stub address (0.0.0.0, 127.x, a private range) for a public site is a block page.
        if !systemV4.isEmpty, systemV4.allSatisfy(isReserved), !union.allSatisfy(isReserved) { return .spoofed }
        if !systemV4.isDisjoint(with: union) { return .agrees }
        // Big sites hand out different addresses per resolver: only call it
        // spoofing when the public resolvers agree with each other.
        let agree = publicAnswers.count >= 2 && publicAnswers.indices.allSatisfy { a in
            publicAnswers.indices.allSatisfy { b in a == b || !publicAnswers[a].isDisjoint(with: publicAnswers[b]) }
        }
        return agree ? .spoofed : .unknown
    }

    /// The verdict for one site. Spoofed DNS comes first (a block page can
    /// open with status 200); a site that opens directly is not blocked; an
    /// address that does not answer even with another site's name, while a
    /// known site does, is an IP block; anything else is DPI.
    /// `addressAnswers` and `controlAnswers` are nil when not tested.
    public static func kind(dns: DNSVerdict, opensDirectly: Bool, addressAnswers: Bool?, controlAnswers: Bool?) -> BlockKind {
        if dns == .spoofed { return .dns }
        if opensDirectly { return .none }
        if addressAnswers == false && controlAnswers == true { return .ip }
        return .dpi
    }

    public static func isIPv4(_ s: String) -> Bool { ipv4Bytes(s) != nil }

    /// 0.0.0.0/8, 10/8, 127/8, 169.254/16, 172.16/12, 192.168/16.
    public static func isReserved(_ s: String) -> Bool {
        guard let b = ipv4Bytes(s) else { return false }
        return b[0] == 0 || b[0] == 10 || b[0] == 127 || (b[0] == 169 && b[1] == 254)
            || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168)
    }

    private static func ipv4Bytes(_ s: String) -> [UInt8]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let bytes = parts.compactMap { $0.count <= 3 && $0.allSatisfy(\.isASCII) ? UInt8($0) : nil }
        return bytes.count == 4 ? bytes : nil
    }
}

/// RFC 8484 DNS-over-HTTPS in wire format: a hand-built A query and a parser
/// for the A records of the answer.
public enum DNSMessage {
    /// A query for the A records of `host`, id 0 (RFC 8484 4.1), recursion desired.
    public static func query(host: String) -> Data? {
        var out: [UInt8] = [0, 0, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]
        let labels = host.lowercased().split(separator: ".")
        guard !labels.isEmpty else { return nil }
        for label in labels {
            let bytes = Array(label.utf8)
            guard (1...63).contains(bytes.count) else { return nil }
            out.append(UInt8(bytes.count))
            out += bytes
        }
        out += [0, 0, 1, 0, 1]
        return out.count <= 512 ? Data(out) : nil
    }

    /// The query as the `dns` parameter of a GET request (base64url, no padding).
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The IPv4 addresses in the answer section. NXDOMAIN gives an empty list;
    /// a malformed message or another error gives nil.
    public static func addresses(in data: Data) -> [String]? {
        let b = [UInt8](data)
        guard b.count >= 12 else { return nil }
        let rcode = b[3] & 0x0F
        if rcode == 3 { return [] }
        guard rcode == 0 else { return nil }
        let qd = Int(b[4]) << 8 | Int(b[5])
        let an = Int(b[6]) << 8 | Int(b[7])
        var i = 12
        func skipName() -> Bool {
            while i < b.count {
                let len = b[i]
                if len == 0 { i += 1; return true }
                if len & 0xC0 == 0xC0 { i += 2; return i <= b.count }
                i += Int(len) + 1
            }
            return false
        }
        for _ in 0..<qd {
            guard skipName(), i + 4 <= b.count else { return nil }
            i += 4
        }
        var out: [String] = []
        for _ in 0..<an {
            guard skipName(), i + 10 <= b.count else { return nil }
            let type = Int(b[i]) << 8 | Int(b[i + 1])
            let length = Int(b[i + 8]) << 8 | Int(b[i + 9])
            i += 10
            guard i + length <= b.count else { return nil }
            if type == 1 && length == 4 {
                out.append(b[i..<i + 4].map(String.init).joined(separator: "."))
            }
            i += length
        }
        return out
    }
}
