import Foundation
import Synchronization
import ZapretMacKit

/// A helper for the self-test and snapshots: nothing runs as root and pf is
/// never touched. It records every call, checks the arguments with the
/// helper's own rules, and runs a local tpws in SOCKS mode on the requested
/// port, so readiness checks pass as they would with the real helper.
nonisolated final class FakeHelperClient: HelperCalling {
    private struct State {
        var calls: [String] = []
        var arguments: [[String]] = []
        var handle: (any TPWSHandle)?
        var port = 0
        var connectionLost: (@Sendable () -> Void)?
        var removed = false
    }

    private let state = Mutex(State())
    private let folders = HelperArguments.allowedFolders(home: NSHomeDirectory())

    init() {}

    /// Every call so far, oldest first: "start", "stop", "status", "cleanUp".
    var calls: [String] { state.withLock { $0.calls } }
    /// The arguments of every start, oldest first.
    var startedArguments: [[String]] { state.withLock { $0.arguments } }
    var isRunning: Bool { state.withLock { $0.handle?.isRunning == true } }
    func count(_ call: String) -> Int { calls.filter { $0 == call }.count }

    func setConnectionLost(_ handler: (@Sendable () -> Void)?) {
        state.withLock { $0.connectionLost = handler }
    }

    func startTransparent(port: Int, arguments: [String]) async -> String? {
        state.withLock {
            $0.calls.append("start")
            $0.arguments.append(arguments)
        }
        if state.withLock({ $0.removed }) { return "The helper is not installed." }
        guard TPWSCommand.isValidPort(port) else { return "bad port \(port)" }
        if let problem = HelperArguments.problem(in: arguments, allowedFolders: folders) { return "refused: \(problem)" }
        stopLocal()
        // The helper's arguments, in SOCKS mode as the user instead of root.
        let command = TPWSCommand(port: port, strategy: arguments, scope: .allSites, debug: false)
        let handle: any TPWSHandle
        do { handle = try LocalTPWSRunner().start(command, output: nil, exit: nil) } catch {
            return "could not start tpws: \(error.localizedDescription)"
        }
        state.withLock {
            $0.handle = handle
            $0.port = port
        }
        // Like the helper: answer only once tpws takes connections.
        for _ in 0..<50 {
            if LocalTPWSRunner.isListening(port) { return nil }
            guard handle.isRunning else { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        stopLocal()
        return "tpws did not start listening on port \(port)"
    }

    func stopTransparent() async -> String? {
        state.withLock { $0.calls.append("stop") }
        stopLocal()
        return nil
    }

    func status() async -> HelperStatus? {
        state.withLock { value in
            value.calls.append("status")
            let running = value.handle?.isRunning == true
            return HelperStatus(running: running, port: running ? value.port : 0, pfTokenPresent: running,
                                tpwsPID: running ? value.handle?.pid ?? 0 : 0)
        }
    }

    func cleanUp() async -> String? {
        state.withLock { $0.calls.append("cleanUp") }
        stopLocal()
        return nil
    }

    /// The helper was removed in System Settings: its connection drops, tpws
    /// stops, and later starts fail.
    func remove() {
        state.withLock { $0.removed = true }
        dropConnection()
    }

    /// The helper went away (it crashed, or was removed).
    func dropConnection() {
        let handler = state.withLock { value -> (@Sendable () -> Void)? in
            defer { value.connectionLost = nil }
            return value.connectionLost
        }
        stopLocal()
        handler?()
    }

    private func stopLocal() {
        let handle = state.withLock { value -> (any TPWSHandle)? in
            defer { value.handle = nil; value.port = 0 }
            return value.handle
        }
        handle?.stop()
    }
}
