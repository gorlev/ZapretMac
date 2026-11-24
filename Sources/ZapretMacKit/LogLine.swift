import Foundation

/// One line of tpws output, sorted into a kind for color and counting.
public struct LogLine: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case info, connection, target, error }

    public let id: Int
    public let date: Date
    public let text: String
    public let kind: Kind
    /// The site name for "target" lines: hostname='example.com'.
    public let host: String?

    public init(id: Int, date: Date = .now, text: String) {
        self.id = id
        self.date = date
        self.text = text
        self.host = Self.host(in: text)
        self.kind = Self.kind(of: text, host: host)
    }

    static func kind(of text: String, host: String?) -> Kind {
        let lower = text.lowercased()
        if lower.contains("error") || lower.contains("fail") || lower.contains("could not")
            || lower.contains("cannot") || lower.contains("invalid") || lower.contains("bad value")
            || lower.contains("address already in use") { return .error }
        if host != nil { return .target }
        if text.contains("connected from") { return .connection }
        return .info
    }

    static func host(in text: String) -> String? {
        guard let start = text.range(of: "hostname='") else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.firstIndex(of: "'") else { return nil }
        let host = String(rest[..<end])
        return host.isEmpty ? nil : host
    }
}

/// Formats a running time like "1 h 05 min" or "42 s".
public enum Uptime {
    public static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return String(localized: "\(s) s", bundle: .main) }
        if s < 3600 { return String(localized: "\(s / 60) min", bundle: .main) }
        let minutes = String(format: "%02d", (s % 3600) / 60)
        return String(localized: "\(s / 3600) h \(minutes) min", bundle: .main)
    }
}
