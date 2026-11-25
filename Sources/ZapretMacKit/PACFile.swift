import Foundation

/// An automatic proxy configuration (PAC) script that sends only listed
/// sites and their subdomains to tpws; everything else connects directly.
/// Excluded sites win over listed ones, as in tpws.
public enum PACFile {
    public static let path = "/proxy.pac"
    public static let contentType = "application/x-ns-proxy-autoconfig"

    /// What a listed host gets: SOCKS5, then SOCKS, then direct when tpws
    /// does not answer.
    public static func proxy(port: Int) -> String {
        "SOCKS5 127.0.0.1:\(port); SOCKS 127.0.0.1:\(port); DIRECT"
    }

    /// The script. The lists become objects, and FindProxyForURL walks the
    /// host's suffixes (a.b.c, b.c, c), so a long list costs a few lookups.
    public static func script(include: [String], exclude: [String], port: Int) -> String {
        """
        // ZapretMac: only the sites in your list go through tpws.
        var proxy = \(literal(proxy(port: port)));
        var include = \(object(include));
        var exclude = \(object(exclude));
        var has = Object.prototype.hasOwnProperty;

        function FindProxyForURL(url, host) {
            var h = String(host).toLowerCase();
            if (h.charAt(h.length - 1) == ".") h = h.substring(0, h.length - 1);
            var listed = false;
            while (h.length > 0) {
                if (has.call(exclude, h)) return "DIRECT";
                if (has.call(include, h)) listed = true;
                var dot = h.indexOf(".");
                if (dot < 0) break;
                h = h.substring(dot + 1);
            }
            return listed ? proxy : "DIRECT";
        }

        """
    }

    /// The domains as a JavaScript object literal, one key per domain.
    static func object(_ domains: [String]) -> String {
        let keys = Set(domains.map(normalize).filter { !$0.isEmpty }).sorted()
        guard !keys.isEmpty else { return "{}" }
        return "{\n" + keys.map { "    \(literal($0)): 1" }.joined(separator: ",\n") + "\n}"
    }

    static func normalize(_ domain: String) -> String {
        var d = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while d.hasPrefix(".") { d.removeFirst() }
        while d.hasSuffix(".") { d.removeLast() }
        return d
    }

    /// A JavaScript string literal.
    static func literal(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case _ where scalar.value < 0x20 || scalar.value == 0x2028 || scalar.value == 0x2029:
                out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
