import CFNetwork
import Foundation
import ZapretMacKit

/// Opens one address twice, once directly and once through tpws, and
/// compares. A site that fails directly but opens through tpws shows the
/// strategy works.
enum SiteCheck {
    enum Outcome: Equatable, Sendable {
        case ok(status: Int, milliseconds: Int)
        case failed(String)

        var isOK: Bool { if case .ok = self { true } else { false } }
    }

    struct Result: Equatable, Sendable {
        var direct: Outcome
        var throughZapret: Outcome?
    }

    static func url(from text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    /// Several addresses typed one per line or separated by spaces, commas, or
    /// semicolons (the Sites list's rules). Repeats of a host are dropped.
    static func urls(from text: String) -> [URL] {
        var seen = Set<String>()
        return Domains.pieces(text).compactMap(url(from:)).filter { seen.insert($0.host?.lowercased() ?? "").inserted }
    }

    static func run(_ url: URL, port: Int?) async -> Result {
        async let direct = fetch(url, socksPort: nil)
        if let port {
            async let via = fetch(url, socksPort: port, retry: true)
            return await Result(direct: direct, throughZapret: via)
        }
        return await Result(direct: direct, throughZapret: nil)
    }

    /// `timeout` is how long to wait for an answer; the whole load gets 2 s more.
    /// Through the proxy, a "proxy could not connect" answer is tried once more:
    /// tpws reports it when its own lookup or connection to the site was slow.
    /// Only the site check retries; for a strategy trial a failure is the answer.
    /// `tls` pins the TLS version (S-102); nil lets the system choose.
    nonisolated static func fetch(_ url: URL, socksPort: Int?, timeout: TimeInterval = 8, retry: Bool = false,
                                  tls: TLSVersion? = nil) async -> Outcome {
        let first = await fetchOnce(url, socksPort: socksPort, timeout: timeout, tls: tls)
        guard retry, socksPort != nil, case .failed(let reason) = first, reason == proxyFailure else { return first }
        try? await Task.sleep(for: .milliseconds(300))
        return await fetchOnce(url, socksPort: socksPort, timeout: timeout, tls: tls)
    }

    nonisolated private static var proxyFailure: String { String(localized: "Could not connect") }

    nonisolated private static func fetchOnce(_ url: URL, socksPort: Int?, timeout: TimeInterval, tls: TLSVersion?) async -> Outcome {
        let config = URLSessionConfiguration.ephemeral
        if let tls {
            // Like curl's --tlsv1.3, and --tlsv1.2 --tls-max 1.2.
            let version: tls_protocol_version_t = tls == .tls13 ? .TLSv13 : .TLSv12
            config.tlsMinimumSupportedProtocolVersion = version
            config.tlsMaximumSupportedProtocolVersion = version
        }
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 2
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // An empty dictionary means no proxy at all, not even the system one.
        if let socksPort {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable as String: 1,
                kCFNetworkProxiesSOCKSProxy as String: "127.0.0.1",
                kCFNetworkProxiesSOCKSPort as String: socksPort,
            ]
        } else {
            config.connectionProxyDictionary = [:]
        }
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let start = Date.now
        do {
            let (_, response) = try await session.data(for: request)
            let ms = Int(Date.now.timeIntervalSince(start) * 1000)
            return .ok(status: (response as? HTTPURLResponse)?.statusCode ?? 0, milliseconds: ms)
        } catch let error as URLError {
            return .failed(describe(error))
        } catch let error as NSError where error.domain == kCFErrorDomainCFNetwork as String {
            // 306 / 310: the (SOCKS) proxy could not reach the site.
            return .failed([306, 310].contains(error.code) ? proxyFailure : error.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    nonisolated private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut: String(localized: "Timed out")
        case .networkConnectionLost: String(localized: "Connection reset")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
            String(localized: "Secure connection failed")
        case .cannotFindHost, .dnsLookupFailed: String(localized: "Site not found")
        case .cannotConnectToHost: String(localized: "Could not connect")
        case .notConnectedToInternet: String(localized: "No internet")
        default: error.localizedDescription
        }
    }
}
