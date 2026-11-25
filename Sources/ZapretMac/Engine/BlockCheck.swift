import Darwin
import Foundation
import Network
import Synchronization
import ZapretMacKit

/// The short diagnosis before a scan (S-101), after zapret blockcheck's
/// `check_dns_spoof` and `check_dpi_ip_block`: is the site's DNS answer
/// changed, is its address blocked, or does the filter read its name?
/// Only the host being checked goes to the public DNS resolvers.
enum BlockCheck {
    /// Looks up a host's addresses; nil when there is no answer.
    typealias Resolver = @Sendable (String) async -> [String]?

    /// Public DNS-over-HTTPS resolvers (RFC 8484 wire format).
    nonisolated static let dohServers = [
        "https://cloudflare-dns.com/dns-query",
        "https://dns.google/dns-query",
        "https://dns.quad9.net/dns-query",
    ].compactMap(URL.init(string:))

    /// A site no filter blocks, used as the name in the address test and as the control.
    nonisolated static let unblockedHost = "iana.org"

    /// The DNS half: the system answer, the public answers, and the verdict.
    struct DNSResult: Sendable {
        var verdict: DNSVerdict
        /// The public resolvers' addresses, most agreed first.
        var publicAddresses: [String]
        var system: [String]?
    }

    nonisolated static let systemResolver: Resolver = { await resolveWithSystem($0) }

    /// The whole diagnosis of one host.
    @concurrent nonisolated static func diagnose(host: String, opensDirectly: Bool,
                                                 resolver: Resolver = systemResolver) async -> BlockKind {
        let dns = await checkDNS(host: host, resolver: resolver)
        return await finish(dns, opensDirectly: opensDirectly, resolver: resolver)
    }

    /// Asks the system resolver and every public resolver at the same time.
    @concurrent nonisolated static func checkDNS(host: String, resolver: Resolver = systemResolver) async -> DNSResult {
        async let system = resolver(host)
        let publicAnswers = await dohAll(host)
        let systemAnswer = await system
        var counts: [String: Int] = [:]
        for answer in publicAnswers { for address in Set(answer ?? []) { counts[address, default: 0] += 1 } }
        let addresses = counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
        return DNSResult(verdict: BlockDiagnosis.dnsVerdict(system: systemAnswer, doh: publicAnswers),
                         publicAddresses: addresses, system: systemAnswer)
    }

    /// The verdict, with the address test when the site failed directly and its DNS looks right.
    @concurrent nonisolated static func finish(_ dns: DNSResult, opensDirectly: Bool,
                                               resolver: Resolver = systemResolver) async -> BlockKind {
        var addressAnswers: Bool?
        var controlAnswers: Bool?
        if dns.verdict != .spoofed && !opensDirectly {
            let targets = Array((dns.publicAddresses.isEmpty ? (dns.system ?? []).filter(BlockDiagnosis.isIPv4) : dns.publicAddresses).prefix(2))
            if !targets.isEmpty {
                async let control = controlSiteAnswers(resolver: resolver)
                // The site's real address with an unblocked name: blocked only if no address answers.
                var any = false
                await withTaskGroup(of: Bool.self) { group in
                    for ip in targets { group.addTask { await tlsAnswers(ip: ip, serverName: unblockedHost) } }
                    for await ok in group where ok { any = true; group.cancelAll() }
                }
                addressAnswers = any
                controlAnswers = await control
            }
        }
        return BlockDiagnosis.kind(dns: dns.verdict, opensDirectly: opensDirectly,
                                   addressAnswers: addressAnswers, controlAnswers: controlAnswers)
    }

    /// The unblocked site on its own address with its own name: if that fails
    /// too, there is no internet and nothing can be said about the address.
    @concurrent nonisolated private static func controlSiteAnswers(resolver: Resolver) async -> Bool {
        var address = await doh(unblockedHost, server: dohServers[0])?.first
        if address == nil { address = await resolver(unblockedHost)?.first(where: BlockDiagnosis.isIPv4) }
        guard let address else { return false }
        return await tlsAnswers(ip: address, serverName: unblockedHost)
    }

    // MARK: - System resolver

    /// getaddrinfo for IPv4 on a background queue; nil when there is no answer.
    nonisolated static func resolveWithSystem(_ host: String) async -> [String]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = SOCK_STREAM
                var list: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { freeaddrinfo(first) }
                var out: [String] = []
                var node: UnsafeMutablePointer<addrinfo>? = first
                while let current = node {
                    if current.pointee.ai_family == AF_INET, let sa = current.pointee.ai_addr {
                        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                            var addr = sin.pointee.sin_addr
                            _ = inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                        }
                        let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        if !out.contains(text) { out.append(text) }
                    }
                    node = current.pointee.ai_next
                }
                continuation.resume(returning: out.isEmpty ? nil : out)
            }
        }
    }

    // MARK: - DNS over HTTPS

    @concurrent nonisolated static func dohAll(_ host: String) async -> [[String]?] {
        await withTaskGroup(of: (Int, [String]?).self) { group in
            for (i, server) in dohServers.enumerated() { group.addTask { (i, await doh(host, server: server)) } }
            var out = [[String]?](repeating: nil, count: dohServers.count)
            for await (i, answer) in group { out[i] = answer }
            return out
        }
    }

    /// One A query over HTTPS, never through a proxy. nil when it fails.
    nonisolated static func doh(_ host: String, server: URL, timeout: TimeInterval = 4) async -> [String]? {
        guard let query = DNSMessage.query(host: host),
              var parts = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
        parts.queryItems = [URLQueryItem(name: "dns", value: DNSMessage.base64URL(query))]
        guard let url = parts.url else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return DNSMessage.addresses(in: data)
    }

    // MARK: - Address test

    /// Opens a TLS connection to `ip`:443 naming `serverName`. The address
    /// answers if the handshake finishes or the server replies with a TLS
    /// alert (it does not know the name); a timeout, reset, or refusal means
    /// it does not. The certificate is not checked and nothing is sent after.
    nonisolated static func tlsAnswers(ip: String, serverName: String, timeout: TimeInterval = 4) async -> Bool {
        let queue = DispatchQueue(label: "BlockCheck.tls")
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, serverName)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Int(timeout)
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.preferNoProxies = true
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: 443, using: parameters)
        let done = Mutex(false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                @Sendable func end(_ answers: Bool) {
                    guard done.withLock({ old in defer { old = true }; return !old }) else { return }
                    connection.cancel()
                    continuation.resume(returning: answers)
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: end(true)
                    // A TLS alert (the server does not know the name) can come
                    // as waiting or as failed: either way the address answered.
                    case .failed(let error), .waiting(let error):
                        if case .tls = error { end(true) } else { end(false) }
                    case .cancelled: end(false)
                    default: break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) { end(false) }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
