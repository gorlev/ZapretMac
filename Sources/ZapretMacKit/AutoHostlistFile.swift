import Foundation

/// The file tpws appends sites to with `--hostlist-auto` (S-100): one host
/// per line, written by tpws, read and trimmed by the app.
public enum AutoHostlistFile {
    /// The sites in the file, in the order tpws added them, each once.
    /// Blank lines and `#` comments are skipped; hosts are lowercased.
    public static func sites(in text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let host = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard !host.isEmpty, !host.hasPrefix("#"), seen.insert(host).inserted else { continue }
            out.append(host)
        }
        return out
    }

    /// The file without `removed`: what is left, one per line.
    public static func contents(of text: String, removing removed: Set<String>) -> String {
        let kept = sites(in: text).filter { !removed.contains($0) }
        return kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n"
    }
}
