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
    /// tpws writes its process id here, so a tpws left behind by a crash can be found.
    public var pidFile: String?

    public init(port: Int, strategy: [String], scope: Scope,
                hostlistPath: String? = nil, excludePath: String? = nil, debug: Bool = true,
                pidFile: String? = nil) {
        self.port = port
        self.strategy = strategy
        self.scope = scope
        self.hostlistPath = hostlistPath
        self.excludePath = excludePath
        self.debug = debug
        self.pidFile = pidFile
    }

    public var arguments: [String] {
        var out = ["--socks", "--bind-addr=127.0.0.1", "--port=\(port)"]
        if debug { out.append("--debug=1") }
        if let pidFile { out.append("--pidfile=\(pidFile)") }
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
