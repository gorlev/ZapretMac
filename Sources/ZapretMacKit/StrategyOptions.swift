import Foundation

/// The tpws desync options a strategy can set, as a form-friendly struct.
/// `arguments` turns it into tpws flags, `init(arguments:)` reads flags back,
/// and any flag the form does not know stays in `extra`.
public struct StrategyOptions: Equatable, Sendable, Codable {
    /// --split-pos, e.g. "1,midsld". Empty means no split.
    public var splitPositions = ""
    public var disorder = false
    public var oob = false
    /// --tlsrec, e.g. "sniext+1". Empty means one TLS record.
    public var tlsRecord = ""
    public var splitAnyProtocol = false

    // HTTP header tricks
    public var hostCase = false
    public var domainCase = false
    public var hostDot = false
    public var hostTab = false
    public var hostNoSpace = false
    public var methodEOL = false
    public var methodSpace = false
    public var unixEOL = false

    /// --filter-tcp, e.g. "80,443". Empty means every port.
    public var tcpPorts = ""
    /// Flags the form does not cover, kept as written.
    public var extra: [String] = []

    public init() {}

    nonisolated(unsafe) private static let flags: [(String, WritableKeyPath<StrategyOptions, Bool>)] = [
        ("--disorder", \.disorder),
        ("--oob", \.oob),
        ("--split-any-protocol", \.splitAnyProtocol),
        ("--hostcase", \.hostCase),
        ("--domcase", \.domainCase),
        ("--hostdot", \.hostDot),
        ("--hosttab", \.hostTab),
        ("--hostnospace", \.hostNoSpace),
        ("--methodeol", \.methodEOL),
        ("--methodspace", \.methodSpace),
        ("--unixeol", \.unixEOL),
    ]

    nonisolated(unsafe) private static let values: [(String, WritableKeyPath<StrategyOptions, String>)] = [
        ("--split-pos", \.splitPositions),
        ("--tlsrec", \.tlsRecord),
        ("--filter-tcp", \.tcpPorts),
    ]

    /// The tpws flags, in a stable order.
    public var arguments: [String] {
        var out: [String] = []
        if !tcpPorts.trimmed.isEmpty { out.append("--filter-tcp=\(tcpPorts.compact)") }
        if !tlsRecord.trimmed.isEmpty { out.append("--tlsrec=\(tlsRecord.compact)") }
        if !splitPositions.trimmed.isEmpty { out.append("--split-pos=\(splitPositions.compact)") }
        for (flag, path) in Self.flags where self[keyPath: path] { out.append(flag) }
        out.append(contentsOf: extra)
        return out
    }

    /// Reads tpws flags. Unknown flags go to `extra`.
    public init(arguments: [String]) {
        self.init()
        for arg in arguments {
            let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
            let name = parts[0]
            if parts.count == 2, let path = Self.values.first(where: { $0.0 == name })?.1 {
                self[keyPath: path] = parts[1]
            } else if parts.count == 1, let path = Self.flags.first(where: { $0.0 == name })?.1 {
                self[keyPath: path] = true
            } else {
                extra.append(arg)
            }
        }
    }

    /// Reads a command-line string such as "--split-pos=1 --disorder".
    public init(commandLine: String) {
        self.init(arguments: CommandLineWords.split(commandLine))
    }

    public var commandLine: String { arguments.joined(separator: " ") }

    /// A short human summary for cards: "Split 1,midsld · Disorder".
    public var summary: String {
        var parts: [String] = []
        if !tlsRecord.trimmed.isEmpty { parts.append("TLS records at \(tlsRecord.compact)") }
        if !splitPositions.trimmed.isEmpty { parts.append("Split at \(splitPositions.compact)") }
        if disorder { parts.append("Disorder") }
        if oob { parts.append("OOB byte") }
        let http = [hostCase, domainCase, hostDot, hostTab, hostNoSpace, methodEOL, methodSpace, unixEOL]
            .filter { $0 }.count
        if http > 0 { parts.append(http == 1 ? "1 HTTP trick" : "\(http) HTTP tricks") }
        if !extra.isEmpty { parts.append("+\(extra.count) more") }
        return parts.isEmpty ? "No changes to traffic" : parts.joined(separator: " · ")
    }
}

/// Splits a command line on spaces, keeping quoted parts together.
public enum CommandLineWords {
    public static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var hasWord = false
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                hasWord = true
            } else if ch.isWhitespace {
                if hasWord { words.append(current); current = ""; hasWord = false }
            } else {
                current.append(ch)
                hasWord = true
            }
        }
        if hasWord { words.append(current) }
        return words
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// "1, midsld" -> "1,midsld"
    var compact: String { filter { !$0.isWhitespace } }
}
