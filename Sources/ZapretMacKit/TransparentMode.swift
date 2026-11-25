import Foundation

// Transparent mode: a root helper runs tpws with pf rules, so every app's web
// traffic goes through tpws without a proxy setting. This file holds the
// parts both the app and the helper use: names, the pf rules, the check on
// the tpws arguments the app sends, and the XPC protocol.

/// Names and numbers shared by the app and the helper.
public enum HelperInfo {
    /// The launchd label and the mach service name of the helper.
    public static let machServiceName = "com.gorlev.zapretmac.helper"
    /// The LaunchDaemon plist inside Contents/Library/LaunchDaemons.
    public static let plistName = "com.gorlev.zapretmac.helper.plist"
    /// The helper binary, relative to the app bundle.
    public static let bundleProgram = "Contents/MacOS/ZapretMacHelper"
    /// The app that may talk to the helper.
    public static let appBundleID = "com.gorlev.zapretmac"
    /// Raised when the XPC protocol changes, so the app can tell an old helper.
    public static let protocolVersion = 1
    /// macOS's own pf.conf loads `rdr-anchor "com.apple/*"` and `anchor "com.apple/*"`,
    /// so a sub-anchor there needs no change to /etc/pf.conf.
    public static let anchor = "com.apple/zapretmac"
}

/// The pf anchor text for transparent mode, after zapret's macOS setup:
/// traffic to the web ports that does not come from root is routed to lo0
/// and redirected to tpws. tpws runs as root, so its own traffic is exempt
/// and does not loop. IPv4 only for now.
public enum PFRules {
    public static let defaultPorts = [80, 443]

    public static func anchorText(port: Int, ports: [Int] = defaultPorts) -> String {
        let list = "{" + ports.map(String.init).joined(separator: ",") + "}"
        return """
        rdr pass on lo0 inet proto tcp from !127.0.0.0/8 to any port \(list) -> 127.0.0.1 port \(port)
        pass out route-to (lo0 127.0.0.1) inet proto tcp from any to any port \(list) user { >root }

        """
    }
}

/// Checks the tpws arguments the app sends to the helper. The helper runs
/// tpws as root, so only strategy and list flags that tpws knows get
/// through; the helper adds the port, address, and user itself.
public enum HelperArguments {
    public enum Value: Sendable {
        /// `--flag` only.
        case none
        /// `--flag=value` (a value is required).
        case required
        /// `--flag` or `--flag=value`.
        case optional
        /// `--flag=/absolute/path` inside an allowed folder.
        case path
    }

    /// Flags from tpws.c's option table that change how traffic is split or
    /// which sites a profile applies to. Not here on purpose: --user, --uid,
    /// --daemon, --pidfile, --port, --bind-*, --socks, --enable-pf, --maxfiles,
    /// --connect-bind-addr, --dry-run, --version, --help, and --hostlist-auto*
    /// (tpws would write those files as root).
    public static let allowed: [String: Value] = [
        "hostcase": .none, "hostspell": .required, "hostdot": .none, "hostnospace": .none,
        "hostpad": .required, "domcase": .none, "split-http-req": .required, "split-tls": .required,
        "split-pos": .required, "split-any-protocol": .optional, "disorder": .optional,
        "oob": .optional, "oob-data": .required, "methodspace": .none, "methodeol": .none,
        "hosttab": .none, "unixeol": .none, "tlsrec": .required, "tlsrec-pos": .required,
        "hostlist": .path, "hostlist-domains": .required, "hostlist-exclude": .path,
        "hostlist-exclude-domains": .required, "ipset": .path, "ipset-ip": .required,
        "ipset-exclude": .path, "ipset-exclude-ip": .required,
        "new": .none, "skip": .none, "filter-l3": .required, "filter-tcp": .required, "filter-l7": .required,
        "mss": .required, "fix-seg": .optional, "nosplice": .none,
        "tamper-start": .required, "tamper-cutoff": .required,
        "debug": .optional, "debug-level": .required, "comment": .optional,
        "maxconn": .required, "max-orphan-time": .required, "ipcache-lifetime": .required,
        "ipcache-hostname": .optional, "no-resolve": .none, "resolver-threads": .required,
        "skip-nodelay": .none, "local-rcvbuf": .required, "local-sndbuf": .required,
        "remote-rcvbuf": .required, "remote-sndbuf": .required,
        "local-tcp-user-timeout": .required, "remote-tcp-user-timeout": .required,
    ]

    /// Folders a list file may be in: the app's data folder for the person
    /// who runs the app, and the /tmp folders of test runs.
    public static func allowedFolders(home: String) -> [String] {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        return ["\(home)/Library/Application Support/ZapretMac/"]
    }

    /// Test stores live at /tmp/ZapretMac-<name>-files/.
    public static let testFolderPrefixes = ["/tmp/ZapretMac-", "/private/tmp/ZapretMac-"]

    /// Nil when every argument is fine, otherwise why the first bad one is refused.
    public static func problem(in arguments: [String], allowedFolders: [String]) -> String? {
        if arguments.count > 400 { return "too many arguments" }
        for argument in arguments {
            if let reason = problem(with: argument, allowedFolders: allowedFolders) {
                return "\(argument): \(reason)"
            }
        }
        return nil
    }

    public static func problem(with argument: String, allowedFolders: [String]) -> String? {
        guard argument.hasPrefix("--") else { return "not a flag" }
        guard argument.utf8.count <= 4096 else { return "too long" }
        guard !argument.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            return "control character"
        }
        let body = argument.dropFirst(2)
        let name: String
        let value: String?
        if let equals = body.firstIndex(of: "=") {
            name = String(body[..<equals])
            value = String(body[body.index(after: equals)...])
        } else {
            name = String(body)
            value = nil
        }
        guard let kind = allowed[name] else { return "not allowed" }
        switch kind {
        case .none:
            if value != nil { return "takes no value" }
        case .required:
            if (value ?? "").isEmpty { return "needs a value" }
        case .optional:
            break
        case .path:
            guard let value, !value.isEmpty else { return "needs a file" }
            if !isAllowedPath(value, folders: allowedFolders) { return "file outside the app's folders" }
        }
        // --debug=@file makes tpws write a file as root.
        if name == "debug", let value, !(value.allSatisfy(\.isNumber) || value == "syslog") {
            return "only a level or syslog"
        }
        return nil
    }

    /// An absolute path with no `.` or `..` parts, inside one of the folders.
    public static func isAllowedPath(_ path: String, folders: [String]) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard !parts.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) else { return false }
        if folders.contains(where: { path.hasPrefix($0) && path.count > $0.count }) { return true }
        for prefix in testFolderPrefixes where path.hasPrefix(prefix) {
            // /tmp/ZapretMac-<store>-files/<file>: the first folder after /tmp must be a test folder.
            let rest = path.dropFirst(prefix.count)
            guard let slash = rest.firstIndex(of: "/") else { return false }
            return rest[..<slash].hasSuffix("-files") && rest.index(after: slash) < rest.endIndex
        }
        return false
    }
}

/// The code-signing requirement the helper puts on its XPC clients: the
/// ZapretMac app, signed by the same team as the helper.
public enum ClientRequirement {
    public static func string(teamID: String, bundleID: String = HelperInfo.appBundleID) -> String? {
        // Team IDs are ten letters and digits; anything else could change the requirement's meaning.
        guard teamID.count == 10, teamID.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return nil }
        guard !bundleID.isEmpty, bundleID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else {
            return nil
        }
        return "identifier \"\(bundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}

/// What the helper reports in `status`.
public struct HelperStatus: Equatable, Sendable {
    public var running: Bool
    public var port: Int
    public var pfTokenPresent: Bool
    public var tpwsPID: Int32

    public init(running: Bool, port: Int, pfTokenPresent: Bool, tpwsPID: Int32) {
        self.running = running
        self.port = port
        self.pfTokenPresent = pfTokenPresent
        self.tpwsPID = tpwsPID
    }
}

/// The helper's XPC interface. Replies with a String carry an error
/// message, nil on success.
@objc public protocol ZapretHelperProtocol {
    func version(reply: @escaping @Sendable (Int) -> Void)
    func status(reply: @escaping @Sendable (_ running: Bool, _ port: Int, _ pfTokenPresent: Bool, _ tpwsPID: Int32) -> Void)
    func startTransparent(port: Int, arguments: [String], reply: @escaping @Sendable (String?) -> Void)
    func stopTransparent(reply: @escaping @Sendable (String?) -> Void)
    /// Removes the anchor, releases pf, and stops tpws. Safe to call any time.
    func cleanUp(reply: @escaping @Sendable (String?) -> Void)
}
