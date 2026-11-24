import Foundation

/// Which sites tpws changes traffic for.
public enum Scope: String, CaseIterable, Sendable, Codable {
    case allSites, listOnly
}

/// Builds the full tpws argument list for SOCKS mode.
public struct TPWSCommand: Equatable, Sendable {
    public var port: Int
    public var strategy: [String]
    public var scope: Scope
    /// File with one domain per line, used when `scope == .listOnly`.
    public var hostlistPath: String?
    /// File with domains never to touch. Nil or empty file: no exclude list.
    public var excludePath: String?
    public var debug = true

    public init(port: Int, strategy: [String], scope: Scope,
                hostlistPath: String? = nil, excludePath: String? = nil, debug: Bool = true) {
        self.port = port
        self.strategy = strategy
        self.scope = scope
        self.hostlistPath = hostlistPath
        self.excludePath = excludePath
        self.debug = debug
    }

    public var arguments: [String] {
        var out = ["--socks", "--bind-addr=127.0.0.1", "--port=\(port)"]
        if debug { out.append("--debug=1") }
        if scope == .listOnly, let hostlistPath { out.append("--hostlist=\(hostlistPath)") }
        if let excludePath { out.append("--hostlist-exclude=\(excludePath)") }
        out.append(contentsOf: strategy)
        return out
    }

    /// For the "copy command" button: quoted where needed.
    public func commandLine(binary: String) -> String {
        ([binary] + arguments).map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
    }

    public static func isValidPort(_ port: Int) -> Bool { (1024...65535).contains(port) }
}
