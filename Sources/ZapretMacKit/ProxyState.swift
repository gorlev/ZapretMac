import Foundation

/// The SOCKS proxy of one network service, as `networksetup` reports it.
public struct ProxyState: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var server: String
    public var port: Int

    public init(enabled: Bool, server: String, port: Int) {
        self.enabled = enabled
        self.server = server
        self.port = port
    }

    /// Reads `networksetup -getsocksfirewallproxy <service>`:
    ///   Enabled: No
    ///   Server: 127.0.0.1
    ///   Port: 988
    ///   Authenticated Proxy Enabled: 0
    public init?(networksetupOutput text: String) {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        guard let enabled = values["Enabled"] else { return nil }
        self.enabled = enabled == "Yes"
        self.server = values["Server"] ?? ""
        self.port = Int(values["Port"] ?? "") ?? 0
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
