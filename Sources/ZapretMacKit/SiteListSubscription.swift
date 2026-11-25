import Foundation

/// Unpacks gzip files (RFC 1952): a header, raw DEFLATE data, and an
/// 8-byte trailer. Only the first member is read, like zapret's own lists.
public enum Gzip {
    public enum Failure: Error, Equatable { case notGzip, damaged }

    /// True when the data starts with the gzip magic bytes.
    public static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    public static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b else { throw Failure.notGzip }
        guard bytes[2] == 8 else { throw Failure.damaged }  // 8 = DEFLATE, the only method
        let flags = bytes[3]
        var at = 10
        if flags & 0x04 != 0 {  // FEXTRA: a length, then that many bytes
            guard at + 2 <= bytes.count else { throw Failure.damaged }
            at += 2 + Int(bytes[at]) + Int(bytes[at + 1]) << 8
        }
        for flag in [UInt8(0x08), 0x10] where flags & flag != 0 {  // FNAME, FCOMMENT: zero-terminated
            while at < bytes.count, bytes[at] != 0 { at += 1 }
            at += 1
        }
        if flags & 0x02 != 0 { at += 2 }  // FHCRC
        guard at <= bytes.count - 8 else { throw Failure.damaged }
        let body = Data(bytes[at..<(bytes.count - 8)])
        // Apple's .zlib algorithm is raw DEFLATE, without a zlib header.
        guard let out = try? (body as NSData).decompressed(using: .zlib) as Data else { throw Failure.damaged }
        return out
    }
}

/// Rules for site lists people subscribe to: a text file of domains, one per
/// line, "#" comments, gzip allowed, the same format zapret's hostlists use.
public enum SiteListSubscription {
    public enum Failure: Error, Equatable {
        /// Not text: a web page that is not a list, or an image.
        case notText
        /// Text, but no domain in it.
        case empty
        case tooLarge
        /// A list of domains was expected, and it holds only IP addresses.
        case onlyAddresses
        /// A list of IP addresses was expected, and it holds only domains.
        case onlyDomains
    }

    /// Lists bigger than this are refused (zapret's biggest lists are a few MB).
    public static let maxBytes = 64 << 20
    /// How often a list is downloaded again.
    public static let refreshInterval: TimeInterval = 24 * 60 * 60

    /// The cleaned domains in a downloaded list, parsed like pasted sites.
    public static func domains(from data: Data) throws -> [String] {
        try entries(from: data, kind: .domains)
    }

    /// The cleaned entries of a downloaded list: domains, or IP addresses and
    /// ranges (S-103). In a list of domains, address lines are skipped, so an
    /// IP list subscribed as domains says so instead of feeding the hostlist.
    public static func entries(from data: Data, kind: ListKind) throws -> [String] {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        let raw = Gzip.isGzip(data) ? try Gzip.decompress(data) : data
        guard raw.count <= maxBytes * 4 else { throw Failure.tooLarge }
        guard !raw.prefix(4096).contains(0), let text = String(data: raw, encoding: .utf8) else { throw Failure.notText }
        let trimmed = text.drop(while: \.isWhitespace).prefix(64).lowercased()
        if trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html") { throw Failure.notText }
        let routed = IPRanges.route(text)
        switch kind {
        case .domains:
            guard !routed.domains.isEmpty else { throw routed.addresses.isEmpty ? Failure.empty : Failure.onlyAddresses }
            return routed.domains
        case .addresses:
            guard !routed.addresses.isEmpty else { throw routed.domains.isEmpty ? Failure.empty : Failure.onlyDomains }
            return routed.addresses
        }
    }

    /// The list address someone typed, or nil when it cannot be a list:
    /// https, http, or a local file.
    public static func url(from text: String) -> URL? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.contains(" "), let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "https", "http": return (url.host ?? "").contains(".") || url.host == "localhost" ? url : nil
        case "file": return url.path.isEmpty || url.path == "/" ? nil : url
        default: return nil
        }
    }

    /// The name shown for a list nobody named: the address's last path part
    /// ("russia-blacklist.txt"), or its host when the path is empty.
    public static func defaultName(for url: URL) -> String {
        let last = url.lastPathComponent
        if !last.isEmpty, last != "/" { return last.removingPercentEncoding ?? last }
        return url.host ?? url.absoluteString
    }

    /// True when a list was never downloaded or its last download is a day old.
    public static func isDue(lastUpdated: Date?, now: Date = .now) -> Bool {
        guard let lastUpdated else { return true }
        return now.timeIntervalSince(lastUpdated) >= refreshInterval
    }

    /// The domains tpws reads: the person's own first, then each list's,
    /// each domain once.
    public static func merge(_ own: [String], _ lists: [[String]]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for domain in own + lists.joined() where seen.insert(domain).inserted { out.append(domain) }
        return out
    }

    /// Reads a list file the app wrote with `Domains.fileContents`.
    public static func readFile(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init)
    }
}
