import Foundation

/// One strategy for HTTP and another for HTTPS in one tpws command: two
/// desync profiles, `--filter-tcp=80 <http> --new --filter-tcp=443 <https>`.
public struct StrategyProfiles: Equatable, Sendable {
    public static let separator = "--new"

    public var http: StrategyOptions
    public var https: StrategyOptions

    public init(http: StrategyOptions, https: StrategyOptions) {
        self.http = http
        self.https = https
    }

    /// Reads a joined argument list back: exactly two profiles, one filtered
    /// to port 80 and one to port 443. Nil for anything else.
    public init?(arguments: [String]) {
        let parts = Self.split(arguments)
        guard parts.count == 2 else { return nil }
        let options = parts.map(StrategyOptions.init(arguments:))
        guard let http = options.first(where: { $0.tcpPorts == "80" }),
              let https = options.first(where: { $0.tcpPorts == "443" }) else { return nil }
        self.init(http: http, https: https)
    }

    /// The HTTP profile, `--new`, then the HTTPS profile.
    public var arguments: [String] {
        var h = http
        h.tcpPorts = "80"
        var s = https
        s.tcpPorts = "443"
        return Self.join([h.arguments, s.arguments])
    }

    /// Cuts an argument list into profiles at every `--new`.
    /// A list without `--new` is one profile.
    public static func split(_ arguments: [String]) -> [[String]] {
        var parts: [[String]] = [[]]
        for arg in arguments {
            if arg == separator { parts.append([]) } else { parts[parts.count - 1].append(arg) }
        }
        return parts
    }

    /// Joins profiles with `--new` between them.
    public static func join(_ parts: [[String]]) -> [String] {
        var out: [String] = []
        for (i, part) in parts.enumerated() {
            if i > 0 { out.append(separator) }
            out.append(contentsOf: part)
        }
        return out
    }
}

extension StrategyOptions {
    /// Flags for a second desync profile follow (`--new …`), kept in `extra`.
    public var hasSecondProfile: Bool { extra.contains(StrategyProfiles.separator) }
}
