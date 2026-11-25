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
    /// --hostspell, the exact 4-letter spelling of "Host", e.g. "hoSt". Empty means "host".
    public var hostSpell = ""
    /// --hostpad, bytes of dummy headers before Host:, e.g. "1024". Empty means none.
    public var hostPad = ""

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
        ("--hostspell", \.hostSpell),
        ("--hostpad", \.hostPad),
    ]

    /// The tpws flags, in a stable order.
    public var arguments: [String] {
        var out: [String] = []
        if !tcpPorts.trimmed.isEmpty { out.append("--filter-tcp=\(tcpPorts.compact)") }
        if !tlsRecord.trimmed.isEmpty { out.append("--tlsrec=\(tlsRecord.compact)") }
        if !splitPositions.trimmed.isEmpty { out.append("--split-pos=\(splitPositions.compact)") }
        for (flag, path) in Self.flags where self[keyPath: path] { out.append(flag) }
        if !hostSpell.trimmed.isEmpty { out.append("--hostspell=\(hostSpell.trimmed)") }
        if !hostPad.trimmed.isEmpty { out.append("--hostpad=\(hostPad.compact)") }
        out.append(contentsOf: extra)
        return out
    }

    /// Reads tpws flags. Unknown flags go to `extra`. The form covers the
    /// first desync profile only: from the first `--new` on, the flags stay
    /// verbatim in `extra`, so a joined strategy round-trips unchanged.
    public init(arguments: [String]) {
        self.init()
        for (index, arg) in arguments.enumerated() {
            if arg == StrategyProfiles.separator {
                extra.append(contentsOf: arguments[index...])
                break
            }
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
        if !tlsRecord.trimmed.isEmpty { parts.append(String(localized: "TLS records at \(tlsRecord.compact)", bundle: .main)) }
        if !splitPositions.trimmed.isEmpty { parts.append(String(localized: "Split at \(splitPositions.compact)", bundle: .main)) }
        if disorder { parts.append(String(localized: "Disorder", bundle: .main)) }
        if oob { parts.append(String(localized: "OOB byte", bundle: .main)) }
        let http = [hostCase, domainCase, hostDot, hostTab, hostNoSpace, methodEOL, methodSpace, unixEOL,
                    !hostSpell.trimmed.isEmpty, !hostPad.trimmed.isEmpty]
            .filter { $0 }.count
        if http > 0 { parts.append(String(localized: "\(http) HTTP tricks", bundle: .main)) }
        if !extra.isEmpty { parts.append(String(localized: "+\(extra.count) more", bundle: .main)) }
        return parts.isEmpty ? String(localized: "No changes to traffic", bundle: .main) : parts.joined(separator: " · ")
    }
}

/// A setting that tpws accepts but that does not work on macOS.
public enum MacWarning: Equatable, Sendable {
    /// --oob and --disorder together: macOS resends the out-of-band byte
    /// without the urgent flag, which corrupts the stream. zapret's
    /// blockcheck.sh tests this pair on Linux only.
    case oobWithDisorder
    /// A flag that only does something on Linux, such as --mss or --fix-seg.
    case linuxOnly(flag: String)

    public var message: String {
        switch self {
        case .oobWithDisorder:
            String(localized: "On a Mac, an out-of-band byte and disorder together break connections. Turn on only one of them.", bundle: .main)
        case .linuxOnly(let flag):
            String(localized: "\(flag) only works on Linux. On a Mac it does nothing.", bundle: .main)
        }
    }
}

extension StrategyOptions {
    /// Flags tpws accepts on macOS that only work on Linux.
    static let linuxOnlyFlags = ["--mss", "--fix-seg"]

    /// What in these options does not work on macOS, in form order.
    public var macOSWarnings: [MacWarning] {
        var out: [MacWarning] = []
        if oob && disorder { out.append(.oobWithDisorder) }
        for arg in extra {
            let name = String(arg.split(separator: "=", maxSplits: 1).first ?? "")
            if Self.linuxOnlyFlags.contains(name), !out.contains(.linuxOnly(flag: name)) {
                out.append(.linuxOnly(flag: name))
            }
        }
        return out
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
