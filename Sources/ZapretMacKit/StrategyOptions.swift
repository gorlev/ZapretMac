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

    // Advanced
    /// What `--disorder` applies to: `--disorder`, `--disorder=http`, or `--disorder=tls`.
    public var disorderScope = ProtocolScope.all
    /// What `--oob` applies to: `--oob`, `--oob=http`, or `--oob=tls`.
    public var oobScope = ProtocolScope.all
    /// --oob-data, one character or 0xHEX, e.g. "0x01". Empty means tpws's 0x00.
    public var oobData = ""
    /// --filter-l7, e.g. "http,tls". Empty means every protocol.
    public var protocolFilter = ""
    /// --tamper-start, e.g. "n2" (data block 2) or "100" (byte 100). Empty means from the start.
    public var tamperStart = ""
    /// --tamper-cutoff, e.g. "n2". Empty means no end.
    public var tamperCutoff = ""
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
        ("--oob-data", \.oobData),
        ("--filter-l7", \.protocolFilter),
        ("--tamper-start", \.tamperStart),
        ("--tamper-cutoff", \.tamperCutoff),
    ]

    /// Fields tpws reads once: a second copy stays in `extra` as written.
    private static let singleValues: Set<String> = ["--oob-data", "--filter-l7", "--tamper-start", "--tamper-cutoff"]

    /// The tpws flags, in a stable order.
    public var arguments: [String] {
        var out: [String] = []
        if !tcpPorts.trimmed.isEmpty { out.append("--filter-tcp=\(tcpPorts.compact)") }
        if !tlsRecord.trimmed.isEmpty { out.append("--tlsrec=\(tlsRecord.compact)") }
        if !splitPositions.trimmed.isEmpty { out.append("--split-pos=\(splitPositions.compact)") }
        for (flag, path) in Self.flags where self[keyPath: path] {
            switch flag {
            case "--disorder": out.append(disorderScope.flag(flag))
            case "--oob": out.append(oobScope.flag(flag))
            default: out.append(flag)
            }
        }
        if !hostSpell.trimmed.isEmpty { out.append("--hostspell=\(hostSpell.trimmed)") }
        if !hostPad.trimmed.isEmpty { out.append("--hostpad=\(hostPad.compact)") }
        if !oobData.trimmed.isEmpty { out.append("--oob-data=\(oobData.compact)") }
        if !protocolFilter.trimmed.isEmpty { out.append("--filter-l7=\(protocolFilter.compact)") }
        if !tamperStart.trimmed.isEmpty { out.append("--tamper-start=\(tamperStart.compact)") }
        if !tamperCutoff.trimmed.isEmpty { out.append("--tamper-cutoff=\(tamperCutoff.compact)") }
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
            if parts.count == 2, let path = Self.values.first(where: { $0.0 == name })?.1,
               !(Self.singleValues.contains(name) && !self[keyPath: path].isEmpty) {
                self[keyPath: path] = parts[1]
            } else if name == "--disorder" || name == "--oob", readScoped(name, value: parts.count == 2 ? parts[1] : nil) {
                continue
            } else if parts.count == 1, let path = Self.flags.first(where: { $0.0 == name })?.1 {
                self[keyPath: path] = true
            } else {
                extra.append(arg)
            }
        }
    }

    /// --disorder, --disorder=http, --disorder=tls (and the same for --oob).
    /// False for a second copy or a value tpws does not know: it stays in extra.
    private mutating func readScoped(_ name: String, value: String?) -> Bool {
        guard let scope = value.map(ProtocolScope.init(rawValue:)) ?? .all,
              value == nil || scope != .all else { return false }
        if name == "--disorder" {
            if disorder { return false }
            disorder = true
            disorderScope = scope
        } else {
            if oob { return false }
            oob = true
            oobScope = scope
        }
        return true
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

/// Which traffic `--disorder` or `--oob` applies to.
public enum ProtocolScope: String, CaseIterable, Sendable, Codable {
    case all, http, tls

    /// "--disorder", "--disorder=http", "--disorder=tls".
    func flag(_ name: String) -> String { self == .all ? name : "\(name)=\(rawValue)" }
}

/// The protocols `--filter-l7` can pick.
public enum L7Protocol: String, CaseIterable, Sendable {
    case http, tls, unknown
}

extension StrategyOptions {
    /// Whether --filter-l7 names this protocol. An empty filter names none (and means all).
    public func filters(_ proto: L7Protocol) -> Bool {
        protocolFilter.compact.split(separator: ",").contains { $0 == proto.rawValue }
    }

    /// Adds or removes a protocol from --filter-l7, in tpws's order (http, tls, unknown).
    public mutating func setFilter(_ proto: L7Protocol, _ on: Bool) {
        let chosen = L7Protocol.allCases.filter { $0 == proto ? on : filters($0) }
        protocolFilter = chosen.map(\.rawValue).joined(separator: ",")
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
