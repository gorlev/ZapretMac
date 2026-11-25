import Darwin
import Foundation
import Observation
import Synchronization
import ZapretMacKit

/// Tries strategies against one or more sites, a few at a time, each in its
/// own short-lived tpws on a free port, so the running bypass is never touched.
@Observable
final class StrategyFinder {
    /// One site opened without any bypass.
    struct Direct: Identifiable, Equatable {
        let site: String
        let outcome: SiteCheck.Outcome
        var id: String { site }
    }

    /// What one site's block looks like (S-101), found before the tries start.
    struct Diagnosis: Identifiable, Equatable {
        let site: String
        let kind: BlockKind
        var id: String { site }
    }

    /// One try's results: per site, and per TLS version on thorough https:// scans.
    nonisolated struct TryResult: Sendable {
        var sites: [SiteAttempt]
        var versions: [VersionResult] = []
    }

    /// How many tries run at the same time, each with its own tpws.
    static let parallelTries = 3

    private(set) var trials: [Trial] = []
    /// Every site opened without ZapretMac, in the order given. Empty until checked.
    private(set) var direct: [Direct] = []
    private(set) var isRunning = false
    /// The hosts being tested, in the order given.
    private(set) var sites: [String] = []
    private(set) var depth: ScanDepth = .quick
    /// Every site's diagnosis, in the order given. Empty until diagnosed.
    private(set) var diagnoses: [Diagnosis] = []
    private(set) var isDiagnosing = false
    /// The TLS versions each try uses (thorough scans of https:// sites), and how often each try runs.
    private(set) var versions: [TLSVersion] = []
    private(set) var repeats = 1
    /// The system resolver used by the diagnosis; the self-test puts in a fake one.
    @ObservationIgnored var resolver: BlockCheck.Resolver = BlockCheck.systemResolver
    private var task: Task<Void, Never>?
    /// Bumped on every start, so a stopped run never touches the next one.
    private var run = 0
    @ObservationIgnored private let helpers = Helpers()

    /// The hosts as one line, for messages.
    var site: String { sites.joined(separator: ", ") }
    var ranked: [Trial] { Trial.ranked(trials) }

    /// Snapshots only: makes a finished scan row look like it worked with
    /// TLS 1.3 alone, to show that row's note without a real filter.
    func pretendTLS12FailedForSnapshot(at index: Int) {
        guard trials.indices.contains(index), trials[index].works else { return }
        let versions = trials[index].versions.map { result in
            result.version == .tls12
                ? VersionResult(version: .tls12, sites: result.sites.map { SiteAttempt(site: $0.site, result: .fails("Connection reset")) })
                : result
        }
        trials[index].finish(versions: versions)
    }
    var isDone: Bool { !isRunning && !trials.isEmpty && trials.allSatisfy { $0.status != .waiting && $0.status != .testing } }
    var workingCount: Int { trials.filter(\.works).count }
    var finishedCount: Int { trials.filter { $0.status != .waiting && $0.status != .testing }.count }
    /// Stopped before every try had a result.
    var isStopped: Bool { !isRunning && !trials.isEmpty && !isDone }

    func start(url: URL, strategies: [(id: String, name: String, arguments: [String])],
               depth: ScanDepth = .quick, timeout: TimeInterval = 8, repeats: Int = 1) {
        start(urls: [url], strategies: strategies, depth: depth, timeout: timeout, repeats: repeats)
    }

    /// Every strategy is tried on every site; `timeout` is how long each site may take.
    /// A thorough scan of https:// sites tries TLS 1.3 and TLS 1.2 separately;
    /// with `repeats` above 1 a try works only if every repeat works.
    func start(urls: [URL], strategies: [(id: String, name: String, arguments: [String])],
               depth: ScanDepth = .quick, timeout: TimeInterval = 8, repeats: Int = 1) {
        stop()
        guard !urls.isEmpty else { return }
        run += 1
        let current = run
        let hosts = urls.map { $0.host ?? $0.absoluteString }
        sites = hosts
        self.depth = depth
        let https = urls.allSatisfy { $0.scheme?.lowercased() == "https" }
        let versions: [TLSVersion] = depth == .thorough && https ? TLSVersion.allCases : []
        let repeats = max(1, repeats)
        self.versions = versions
        self.repeats = repeats
        trials = strategies.map { Trial(id: $0.id, name: $0.name, arguments: $0.arguments) }
        direct = []
        diagnoses = []
        isDiagnosing = true
        isRunning = true
        let jobs = trials.map(\.arguments)
        let helpers = helpers
        let resolver = resolver
        task = Task {
            // The DNS comparison runs beside the direct check; the address
            // test only for sites that did not open.
            async let dns = Self.checkDNSAll(hosts, resolver: resolver)
            let outcomes = await Self.fetchAll(urls, socksPort: nil, timeout: timeout)
            let dnsResults = await dns
            guard !Task.isCancelled, run == current else { return }
            direct = zip(hosts, outcomes).map { Direct(site: $0, outcome: $1) }
            let kinds = await Self.diagnoseAll(dnsResults, opens: outcomes.map(\.isOK), resolver: resolver)
            guard !Task.isCancelled, run == current else { return }
            diagnoses = zip(hosts, kinds).map { Diagnosis(site: $0, kind: $1) }
            isDiagnosing = false
            // A sliding window: start a few tries, and a new one as each finishes.
            await withTaskGroup(of: (Int, TryResult?).self) { group in
                var next = 0
                while next < jobs.count {
                    if next >= Self.parallelTries, let (index, attempts) = await group.next() {
                        if Task.isCancelled || run != current { group.cancelAll(); return }
                        record(attempts, at: index)
                    }
                    let index = next, arguments = jobs[index]
                    next += 1
                    trials[index].status = .testing
                    group.addTask {
                        (index, await Self.trial(urls: urls, arguments: arguments, timeout: timeout,
                                                 versions: versions, repeats: repeats, helpers: helpers))
                    }
                }
                for await (index, attempts) in group {
                    if Task.isCancelled || run != current { group.cancelAll(); return }
                    record(attempts, at: index)
                }
            }
            guard !Task.isCancelled, run == current else { return }
            isRunning = false
        }
    }

    /// nil means the try was cancelled; it goes back to waiting.
    private func record(_ result: TryResult?, at index: Int) {
        guard let result else { trials[index].status = .waiting; return }
        if result.versions.isEmpty { trials[index].finish(with: result.sites) } else { trials[index].finish(versions: result.versions) }
    }

    /// The sites' DNS checks, all at once, in the given order.
    @concurrent nonisolated static func checkDNSAll(_ hosts: [String], resolver: @escaping BlockCheck.Resolver) async -> [BlockCheck.DNSResult] {
        await withTaskGroup(of: (Int, BlockCheck.DNSResult).self) { group in
            for (i, host) in hosts.enumerated() { group.addTask { (i, await BlockCheck.checkDNS(host: host, resolver: resolver)) } }
            var out = [BlockCheck.DNSResult](repeating: .init(verdict: .unknown, publicAddresses: [], system: nil), count: hosts.count)
            for await (i, result) in group { out[i] = result }
            return out
        }
    }

    /// Every site's verdict, all at once, in the given order.
    @concurrent nonisolated static func diagnoseAll(_ dns: [BlockCheck.DNSResult], opens: [Bool],
                                                    resolver: @escaping BlockCheck.Resolver) async -> [BlockKind] {
        await withTaskGroup(of: (Int, BlockKind).self) { group in
            for (i, result) in dns.enumerated() {
                let ok = i < opens.count && opens[i]
                group.addTask { (i, await BlockCheck.finish(result, opensDirectly: ok, resolver: resolver)) }
            }
            var out = [BlockKind](repeating: .dpi, count: dns.count)
            for await (i, kind) in group { out[i] = kind }
            return out
        }
    }

    /// Cancels every try and stops every tpws the finder started.
    func stop() {
        task?.cancel()
        task = nil
        helpers.terminateAll()
        isRunning = false
        isDiagnosing = false
        for i in trials.indices where trials[i].status == .testing { trials[i].status = .waiting }
    }

    func reset() {
        stop()
        trials = []
        direct = []
        diagnoses = []
        sites = []
    }

    /// Starts tpws with one strategy, opens every site through it at once
    /// (with each TLS version at once, every repeat in turn), stops tpws.
    /// Returns nil when cancelled.
    @concurrent nonisolated static func trial(urls: [URL], arguments: [String], timeout: TimeInterval = 8,
                                              versions: [TLSVersion] = [], repeats: Int = 1,
                                              helpers: Helpers = Helpers()) async -> TryResult? {
        let hosts = urls.map { $0.host ?? $0.absoluteString }
        func allFail(_ reason: String) -> TryResult { TryResult(sites: hosts.map { SiteAttempt(site: $0, result: .fails(reason)) }) }
        guard let port = helpers.reservePort() else { return allFail(String(localized: "No free port")) }
        defer { helpers.release(port) }
        let command = TPWSCommand(port: port, strategy: arguments, scope: .allSites, debug: false)
        // Tries always run as the user, never through the privileged helper.
        let runner = LocalTPWSRunner()
        let process: any TPWSHandle
        do { process = try runner.start(command, output: nil, exit: nil) } catch {
            return allFail(String(localized: "tpws did not start"))
        }
        helpers.track(process, port: port)
        // Never wait forever for tpws to quit: a stuck one is killed.
        defer { process.stop() }
        // Wait until tpws accepts connections, up to a second.
        let plan = TPWSReadinessPlan.trial
        for _ in 0..<plan.attempts {
            if await runner.isReady(port: port) || Task.isCancelled { break }
            try? await Task.sleep(for: plan.interval)
        }
        if Task.isCancelled { return nil }
        guard process.isRunning else { return allFail(String(localized: "tpws refused these flags")) }
        // A hard limit on top of URLSession's own timeouts, so a row can never
        // stay on "Testing…": whatever happens, the try ends.
        let repeats = max(1, repeats)
        let deadline = Double(repeats) * (timeout + 2) + 2
        let result = await withTaskGroup(of: TryResult?.self) { group in
            group.addTask { await runRepeats(urls: urls, port: port, timeout: timeout, versions: versions, repeats: repeats) }
            group.addTask {
                try? await Task.sleep(for: .seconds(deadline))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            if let first { return first }
            let timedOut = hosts.map { SiteAttempt(site: $0, result: .fails(String(localized: "Timed out"))) }
            return TryResult(sites: timedOut, versions: versions.map { VersionResult(version: $0, sites: timedOut) })
        }
        if Task.isCancelled { return nil }
        return result
    }

    /// Every repeat in turn, stopping at the first one where a site fails;
    /// TLS versions side by side.
    @concurrent nonisolated private static func runRepeats(urls: [URL], port: Int, timeout: TimeInterval,
                                                           versions: [TLSVersion], repeats: Int) async -> TryResult {
        let hosts = urls.map { $0.host ?? $0.absoluteString }
        @Sendable func repeated(_ tls: TLSVersion?) async -> [[SiteAttempt]] {
            var runs: [[SiteAttempt]] = []
            for _ in 0..<repeats {
                let outcomes = await fetchAll(urls, socksPort: port, timeout: timeout, tls: tls)
                let attempts = zip(hosts, outcomes).map { host, outcome in
                    switch outcome {
                    case .ok(_, let ms): SiteAttempt(site: host, result: .opens(milliseconds: ms))
                    case .failed(let reason): SiteAttempt(site: host, result: .fails(reason))
                    }
                }
                runs.append(attempts)
                if Task.isCancelled || attempts.contains(where: { !$0.opens }) { break }
            }
            return runs
        }
        guard !versions.isEmpty else { return TryResult(sites: Trial.combine(repeats: await repeated(nil))) }
        let results = await withTaskGroup(of: (Int, VersionResult).self) { group in
            for (i, version) in versions.enumerated() {
                group.addTask { (i, VersionResult(version: version, repeats: await repeated(version))) }
            }
            var out: [(Int, VersionResult)] = []
            for await item in group { out.append(item) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return TryResult(sites: [], versions: results)
    }

    /// Opens every address at the same time; the answers keep the given order.
    @concurrent nonisolated static func fetchAll(_ urls: [URL], socksPort: Int?, timeout: TimeInterval,
                                                 tls: TLSVersion? = nil) async -> [SiteCheck.Outcome] {
        await withTaskGroup(of: (Int, SiteCheck.Outcome).self) { group in
            for (i, url) in urls.enumerated() {
                group.addTask { (i, await SiteCheck.fetch(url, socksPort: socksPort, timeout: timeout, tls: tls)) }
            }
            var out = [SiteCheck.Outcome](repeating: .failed(""), count: urls.count)
            for await (i, outcome) in group { out[i] = outcome }
            return out
        }
    }

    /// The ports and tpws processes of the tries in flight, so parallel tries
    /// never pick the same port and Stop can end every one at once.
    final class Helpers: Sendable {
        private struct State {
            var ports: Set<Int> = []
            var processes: [Int: any TPWSHandle] = [:]
        }
        private let state = Mutex(State())

        nonisolated init() {}

        nonisolated func reservePort() -> Int? {
            for _ in 0..<10 {
                guard let port = StrategyFinder.freePort() else { return nil }
                if state.withLock({ $0.ports.insert(port).inserted }) { return port }
            }
            return nil
        }

        nonisolated func track(_ process: any TPWSHandle, port: Int) {
            state.withLock { $0.processes[port] = process }
        }

        nonisolated func release(_ port: Int) {
            state.withLock {
                $0.ports.remove(port)
                $0.processes[port] = nil
            }
        }

        nonisolated func terminateAll() {
            let running = state.withLock { Array($0.processes.values) }
            for process in running { process.terminate() }
        }
    }

    /// Asks the system for a free TCP port on 127.0.0.1.
    nonisolated static func freePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0
            }
        }
        return bound ? Int(UInt16(bigEndian: addr.sin_port)) : nil
    }
}
