import Foundation

/// Which sites tpws changes traffic for.
public enum Scope: String, CaseIterable, Sendable, Codable {
    case allSites, listOnly
}

/// Builds the full tpws argument list: SOCKS mode, or the part of a
/// Transparent mode command that the app sends to the root helper.
public struct TPWSCommand: Equatable, Sendable {
    /// How tpws is reached.
    public enum Mode: String, Sendable {
        /// A SOCKS proxy on 127.0.0.1, run by the app as the user.
        case socks
        /// Run as root by the helper with pf rules (S-081). The helper adds the
        /// port, address, and user itself and refuses them from the app.
        case transparent
    }

    public var port: Int
    public var strategy: [String]
    public var scope: Scope
    /// File with one domain per line, used when `scope == .listOnly`.
    public var hostlistPath: String?
    /// File with domains never to touch. Nil or empty file: no exclude list.
    public var excludePath: String?
    public var debug = true
    /// tpws writes its process id here, so a tpws left behind by a crash can be found.
    /// SOCKS mode only: the helper tracks its own tpws.
    public var pidFile: String?
    public var mode: Mode
    /// S-100: tpws adds sites whose connections fail to this file by itself.
    public var autoHostlist: AutoHostlist?

    /// tpws `--hostlist-auto`: a site that fails `failThreshold` times within
    /// `failTime` seconds is appended to the file, and the bypass then acts on it.
    public struct AutoHostlist: Equatable, Sendable {
        public var path: String
        public var failThreshold: Int
        public var failTime: Int

        public static let defaultFailThreshold = 3
        public static let defaultFailTime = 60

        public init(path: String, failThreshold: Int = Self.defaultFailThreshold, failTime: Int = Self.defaultFailTime) {
            self.path = path
            self.failThreshold = failThreshold
            self.failTime = failTime
        }

        var arguments: [String] {
            ["--hostlist-auto=\(path)", "--hostlist-auto-fail-threshold=\(failThreshold)",
             "--hostlist-auto-fail-time=\(failTime)"]
        }
    }

    /// Whether tpws gets `--hostlist-auto`. In tpws the auto file is also an
    /// include list, and tpws only watches sites it leaves alone: with All
    /// sites there is nothing to learn, and the option would narrow the bypass
    /// to the learned sites. So only with My list, which it extends. Never in
    /// Transparent mode: tpws runs as root there and would write the file as root
    /// (the helper refuses the flag).
    public var usesAutoHostlist: Bool {
        autoHostlist != nil && scope == .listOnly && mode == .socks
    }

    public init(port: Int, strategy: [String], scope: Scope,
                hostlistPath: String? = nil, excludePath: String? = nil, debug: Bool = true,
                pidFile: String? = nil, mode: Mode = .socks, autoHostlist: AutoHostlist? = nil) {
        self.port = port
        self.strategy = strategy
        self.scope = scope
        self.hostlistPath = hostlistPath
        self.excludePath = excludePath
        self.debug = debug
        self.pidFile = pidFile
        self.mode = mode
        self.autoHostlist = autoHostlist
    }

    /// In Transparent mode: only strategy, list, and debug flags, which is
    /// what `HelperArguments.problem(in:allowedFolders:)` accepts.
    public var arguments: [String] {
        var out: [String] = []
        if mode == .socks { out = ["--socks", "--bind-addr=127.0.0.1", "--port=\(port)"] }
        if debug { out.append("--debug=1") }
        if mode == .socks, let pidFile { out.append("--pidfile=\(pidFile)") }
        // Lists belong to a desync profile: with several profiles (`--new`),
        // every profile gets them, so My list and Never Touch apply to all.
        var lists: [String] = []
        if scope == .listOnly, let hostlistPath { lists.append("--hostlist=\(hostlistPath)") }
        if usesAutoHostlist, let autoHostlist { lists += autoHostlist.arguments }
        if let excludePath { lists.append("--hostlist-exclude=\(excludePath)") }
        let profiles = StrategyProfiles.split(strategy).map { lists + $0 }
        out.append(contentsOf: StrategyProfiles.join(profiles))
        return out
    }

    /// For the "copy command" button: quoted where needed. In Transparent
    /// mode it also shows the flags the helper adds.
    public func commandLine(binary: String) -> String {
        let fixed = mode == .transparent ? HelperInfo.fixedTPWSArguments(port: port) : []
        return ([binary] + fixed + arguments).map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
    }

    public static func isValidPort(_ port: Int) -> Bool { (1024...65535).contains(port) }
}
