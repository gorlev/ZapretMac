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

    /// How many tries run at the same time, each with its own tpws.
    static let parallelTries = 3

    private(set) var trials: [Trial] = []
    /// Every site opened without ZapretMac, in the order given. Empty until checked.
    private(set) var direct: [Direct] = []
    private(set) var isRunning = false
    /// The hosts being tested, in the order given.
    private(set) var sites: [String] = []
    private(set) var depth: ScanDepth = .quick
    private var task: Task<Void, Never>?
    /// Bumped on every start, so a stopped run never touches the next one.
    private var run = 0
    @ObservationIgnored private let helpers = Helpers()

    /// The hosts as one line, for messages.
    var site: String { sites.joined(separator: ", ") }
    var ranked: [Trial] { Trial.ranked(trials) }
    var isDone: Bool { !isRunning && !trials.isEmpty && trials.allSatisfy { $0.status != .waiting && $0.status != .testing } }
    var workingCount: Int { trials.filter(\.works).count }
    var finishedCount: Int { trials.filter { $0.status != .waiting && $0.status != .testing }.count }
    /// Stopped before every try had a result.
    var isStopped: Bool { !isRunning && !trials.isEmpty && !isDone }

    func start(url: URL, strategies: [(id: String, name: String, arguments: [String])],
               depth: ScanDepth = .quick, timeout: TimeInterval = 8) {
        start(urls: [url], strategies: strategies, depth: depth, timeout: timeout)
    }

    /// Every strategy is tried on every site; `timeout` is how long each site may take.
    func start(urls: [URL], strategies: [(id: String, name: String, arguments: [String])],
               depth: ScanDepth = .quick, timeout: TimeInterval = 8) {
        stop()
        guard !urls.isEmpty else { return }
        run += 1
        let current = run
        let hosts = urls.map { $0.host ?? $0.absoluteString }
        sites = hosts
        self.depth = depth
        trials = strategies.map { Trial(id: $0.id, name: $0.name, arguments: $0.arguments) }
        direct = []
        isRunning = true
        let jobs = trials.map(\.arguments)
        let helpers = helpers
        task = Task {
            let outcomes = await Self.fetchAll(urls, socksPort: nil, timeout: timeout)
            guard !Task.isCancelled, run == current else { return }
            direct = zip(hosts, outcomes).map { Direct(site: $0, outcome: $1) }
            // A sliding window: start a few tries, and a new one as each finishes.
            await withTaskGroup(of: (Int, [SiteAttempt]?).self) { group in
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
                        (index, await Self.trial(urls: urls, arguments: arguments, timeout: timeout, helpers: helpers))
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
    private func record(_ attempts: [SiteAttempt]?, at index: Int) {
        if let attempts { trials[index].finish(with: attempts) } else { trials[index].status = .waiting }
    }

    /// Cancels every try and stops every tpws the finder started.
    func stop() {
        task?.cancel()
        task = nil
        helpers.terminateAll()
        isRunning = false
        for i in trials.indices where trials[i].status == .testing { trials[i].status = .waiting }
    }

    func reset() {
        stop()
        trials = []
        direct = []
        sites = []
    }

    /// Starts tpws with one strategy, opens every site through it at once,
    /// stops tpws. Returns nil when cancelled.
    @concurrent nonisolated static func trial(urls: [URL], arguments: [String], timeout: TimeInterval = 8,
                                              helpers: Helpers = Helpers()) async -> [SiteAttempt]? {
        let hosts = urls.map { $0.host ?? $0.absoluteString }
        func allFail(_ reason: String) -> [SiteAttempt] { hosts.map { SiteAttempt(site: $0, result: .fails(reason)) } }
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
        let outcomes = await withTaskGroup(of: [SiteCheck.Outcome]?.self) { group in
            group.addTask { await fetchAll(urls, socksPort: port, timeout: timeout) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout + 4))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? urls.map { _ in SiteCheck.Outcome.failed(String(localized: "Timed out")) }
        }
        if Task.isCancelled { return nil }
        return zip(hosts, outcomes).map { host, outcome in
            switch outcome {
            case .ok(_, let ms): SiteAttempt(site: host, result: .opens(milliseconds: ms))
            case .failed(let reason): SiteAttempt(site: host, result: .fails(reason))
            }
        }
    }

    /// Opens every address at the same time; the answers keep the given order.
    @concurrent nonisolated static func fetchAll(_ urls: [URL], socksPort: Int?, timeout: TimeInterval) async -> [SiteCheck.Outcome] {
        await withTaskGroup(of: (Int, SiteCheck.Outcome).self) { group in
            for (i, url) in urls.enumerated() {
                group.addTask { (i, await SiteCheck.fetch(url, socksPort: socksPort, timeout: timeout)) }
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
