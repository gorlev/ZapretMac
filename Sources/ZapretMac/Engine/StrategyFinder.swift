import Darwin
import Foundation
import Observation
import ZapretMacKit

/// Tries strategies one by one against a site, each in its own short-lived
/// tpws on a free port, so the running bypass is never touched.
@Observable
final class StrategyFinder {
    private(set) var trials: [Trial] = []
    private(set) var direct: SiteCheck.Outcome?
    private(set) var isRunning = false
    private(set) var site = ""
    private var task: Task<Void, Never>?

    var ranked: [Trial] { Trial.ranked(trials) }
    var isDone: Bool { !isRunning && !trials.isEmpty && trials.allSatisfy { $0.status != .waiting && $0.status != .testing } }
    var workingCount: Int { trials.filter(\.works).count }

    func start(url: URL, strategies: [(id: String, name: String, arguments: [String])]) {
        stop()
        site = url.host ?? url.absoluteString
        trials = strategies.map { Trial(id: $0.id, name: $0.name, arguments: $0.arguments) }
        direct = nil
        isRunning = true
        task = Task {
            direct = await SiteCheck.fetch(url, socksPort: nil)
            for index in trials.indices {
                if Task.isCancelled { break }
                trials[index].status = .testing
                let status = await Self.trial(url: url, arguments: trials[index].arguments)
                if Task.isCancelled { trials[index].status = .waiting; break }
                trials[index].status = status
            }
            isRunning = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        for i in trials.indices where trials[i].status == .testing { trials[i].status = .waiting }
    }

    func reset() {
        stop()
        trials = []
        direct = nil
    }

    /// Starts tpws with one strategy, opens the site through it, stops tpws.
    nonisolated static func trial(url: URL, arguments: [String]) async -> Trial.Status {
        guard let port = freePort() else { return .fails(String(localized: "No free port")) }
        let command = TPWSCommand(port: port, strategy: arguments, scope: .allSites, debug: false)
        let process = Process()
        process.executableURL = Engine.binaryURL
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .fails(String(localized: "tpws did not start")) }
        defer {
            process.terminate()
            process.waitUntilExit()
        }
        // Wait until tpws accepts connections, up to a second.
        for _ in 0..<20 {
            if isListening(port) { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard process.isRunning else { return .fails(String(localized: "tpws refused these flags")) }
        switch await SiteCheck.fetch(url, socksPort: port) {
        case .ok(_, let ms): return .works(milliseconds: ms)
        case .failed(let reason): return .fails(reason)
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

    nonisolated static func isListening(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
