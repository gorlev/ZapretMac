import Foundation

/// The SOCKS proxy and the automatic proxy configuration (PAC) of one
/// network service, as `networksetup` reports them.
public struct ProxyState: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var server: String
    public var port: Int
    /// The automatic proxy configuration URL, "" when none is set.
    /// nil: not read (states saved before S-072); restore leaves it alone.
    public var autoProxyURL: String?
    /// Whether the automatic proxy configuration is on. nil: not read.
    public var autoProxyEnabled: Bool?

    public init(enabled: Bool, server: String, port: Int, autoProxyURL: String? = nil, autoProxyEnabled: Bool? = nil) {
        self.enabled = enabled
        self.server = server
        self.port = port
        self.autoProxyURL = autoProxyURL
        self.autoProxyEnabled = autoProxyEnabled
    }

    /// Reads `networksetup -getsocksfirewallproxy <service>`:
    ///   Enabled: No
    ///   Server: 127.0.0.1
    ///   Port: 988
    ///   Authenticated Proxy Enabled: 0
    public init?(networksetupOutput text: String) {
        let values = Self.values(text)
        guard let enabled = values["Enabled"] else { return nil }
        self.enabled = enabled == "Yes"
        self.server = values["Server"] ?? ""
        self.port = Int(values["Port"] ?? "") ?? 0
    }

    /// Reads `networksetup -getautoproxyurl <service>`:
    ///   URL: http://127.0.0.1:1089/proxy.pac
    ///   Enabled: Yes
    /// "(null)" means no URL. Returns nil for anything else.
    public static func autoProxy(fromOutput text: String) -> (url: String, enabled: Bool)? {
        let values = values(text)
        guard let enabled = values["Enabled"], let url = values["URL"] else { return nil }
        return (url == "(null)" ? "" : url, enabled == "Yes")
    }

    /// Adds what `networksetup -getautoproxyurl` printed.
    public mutating func readAutoProxy(_ text: String) {
        let auto = Self.autoProxy(fromOutput: text) ?? (url: "", enabled: false)
        autoProxyURL = auto.url
        autoProxyEnabled = auto.enabled
    }

    private static func values(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        return values
    }

    public func points(to port: Int) -> Bool {
        enabled && server == "127.0.0.1" && self.port == port
    }

    /// Reads `networksetup -listallnetworkservices`: skips the header line
    /// and services marked off with "*".
    public static func services(fromList text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.hasPrefix("An asterisk") && !$0.hasPrefix("*") && !$0.isEmpty }
    }
}

/// How the system proxy sends apps to tpws.
public enum ProxyMode: String, Codable, Sendable {
    /// Every connection goes to the SOCKS proxy.
    case socks
    /// A PAC file sends only listed sites to the SOCKS proxy.
    case pac
}

/// The `networksetup` argument lists that apply and restore the system
/// proxy. Pure, so tests check them without touching the Mac's settings.
public enum ProxyCommands {
    /// SOCKS mode: the SOCKS proxy on, the automatic configuration off.
    /// PAC mode: the automatic configuration on with `pacURL`, SOCKS off.
    public static func apply(services: [String], mode: ProxyMode, port: Int, pacURL: String?) -> [[String]] {
        var commands: [[String]] = []
        for service in services {
            switch mode {
            case .socks:
                commands.append(["-setsocksfirewallproxy", service, "127.0.0.1", String(port)])
                commands.append(["-setsocksfirewallproxystate", service, "on"])
                commands.append(["-setautoproxystate", service, "off"])
            case .pac:
                commands.append(["-setautoproxyurl", service, pacURL ?? ""])
                commands.append(["-setautoproxystate", service, "on"])
                commands.append(["-setsocksfirewallproxystate", service, "off"])
            }
        }
        return commands
    }

    /// Puts back the SOCKS and automatic proxy settings saved before applying.
    /// An auto-proxy state that was never read (nil) is left alone.
    public static func restore(_ previous: [String: ProxyState]) -> [[String]] {
        var commands: [[String]] = []
        for (service, state) in previous.sorted(by: { $0.key < $1.key }) {
            if state.enabled, !state.server.isEmpty {
                commands.append(["-setsocksfirewallproxy", service, state.server, String(state.port)])
                commands.append(["-setsocksfirewallproxystate", service, "on"])
            } else {
                commands.append(["-setsocksfirewallproxystate", service, "off"])
            }
            guard let enabled = state.autoProxyEnabled else { continue }
            let url = state.autoProxyURL ?? ""
            if !url.isEmpty {
                commands.append(["-setautoproxyurl", service, url])
            }
            commands.append(["-setautoproxystate", service, enabled && !url.isEmpty ? "on" : "off"])
        }
        return commands
    }
}
