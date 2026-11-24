import Foundation

/// Cleans what people paste into the domain lists.
public enum Domains {
    /// "https://www.YouTube.com/watch?v=1" -> "youtube.com". Returns nil for
    /// text that is not a domain.
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("#") || s.isEmpty { return nil }
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if let cut = s.firstIndex(where: { "/?#:".contains($0) }) { s = String(s[..<cut]) }
        if s.hasPrefix("*.") { s.removeFirst(2) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        while s.hasSuffix(".") { s.removeLast() }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard s.contains("."), !s.hasPrefix("."), !s.contains(".."),
              s.unicodeScalars.allSatisfy(allowed.contains),
              s.count <= 253 else { return nil }
        return s
    }

    /// Splits pasted text or a file on whitespace, commas, and semicolons,
    /// normalizes each piece, and drops duplicates (keeping order).
    public static func parseList(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let body = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            for piece in body.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" }) {
                if let d = normalize(String(piece)), seen.insert(d).inserted { out.append(d) }
            }
        }
        return out
    }

    /// The hostlist file tpws reads: one domain per line.
    public static func fileContents(_ domains: [String]) -> String {
        domains.isEmpty ? "" : domains.joined(separator: "\n") + "\n"
    }
}
