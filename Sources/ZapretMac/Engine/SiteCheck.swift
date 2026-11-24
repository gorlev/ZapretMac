import CFNetwork
import Foundation

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

    static func run(_ url: URL, port: Int?) async -> Result {
        async let direct = fetch(url, socksPort: nil)
        if let port {
            async let via = fetch(url, socksPort: port)
            return await Result(direct: direct, throughZapret: via)
        }
        return await Result(direct: direct, throughZapret: nil)
    }

    nonisolated static func fetch(_ url: URL, socksPort: Int?) async -> Outcome {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
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
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    nonisolated private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut: "Timed out"
        case .networkConnectionLost: "Connection reset"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
            "Secure connection failed"
        case .cannotFindHost, .dnsLookupFailed: "Site not found"
        case .cannotConnectToHost: "Could not connect"
        case .notConnectedToInternet: "No internet"
        default: error.localizedDescription
        }
    }
}
