import Foundation
import Observation
import ZapretMacKit

/// Keeps tpws running in SOCKS mode through a `TPWSRunner` and collects its output.
@Observable
final class Engine {
    enum State: Equatable {
        case stopped, starting, running
        case failed(String)
    }

    private(set) var state: State = .stopped
    private(set) var lines: [LogLine] = []
    private(set) var startedAt: Date?
    private(set) var connections = 0
    private(set) var recentHosts: [String] = []
    private(set) var hostsSeen: Set<String> = []
    private(set) var commandLine = ""
    /// How many times tpws was restarted after quitting by itself.
    private(set) var autoRestarts = 0
    /// Called once tpws has quit by itself twice within a minute.
    var onFailure: ((String) -> Void)?
    var pid: Int32? { handle?.pid }

    var isOn: Bool { state == .running || state == .starting }

    /// Starts and stops tpws. Local by default; the self-test passes a fake.
    @ObservationIgnored private let runner: any TPWSRunner
    private var handle: (any TPWSHandle)?
    private var nextID = 0
    /// Bumped on every start and stop, so output and exits from an old
    /// process never change the state of a new one.
    private var generation = 0
    private var lastCommand: TPWSCommand?
    private var restarts = TPWSRestartPolicy()
    static let maxLines = 4000

    init(runner: any TPWSRunner = LocalTPWSRunner()) {
        self.runner = runner
    }

    /// Contents/Helpers/tpws inside the app. TPWS_PATH overrides it.
    nonisolated static var binaryURL: URL { LocalTPWSRunner.binaryURL }

    static var binaryExists: Bool { LocalTPWSRunner().isAvailable }

    func start(_ command: TPWSCommand) {
        stop()
        guard runner.isAvailable else {
            state = .failed(String(localized: "tpws is missing from the app. Rebuild it with ./build.sh."))
            return
        }
        generation += 1
        let gen = generation
        lastCommand = command
        connections = 0
        commandLine = command.commandLine(binary: runner.binaryPath)
        append(["$ " + commandLine])

        let handle: any TPWSHandle
        do {
            handle = try runner.start(command, output: { [weak self] text in
                Task { @MainActor in self?.receive(text, generation: gen) }
            }, exit: { [weak self] code in
                Task { @MainActor in self?.ended(code: code, generation: gen) }
            })
        } catch {
            state = .failed(String(localized: "Could not start tpws: \(error.localizedDescription)"))
            return
        }
        self.handle = handle
        state = .starting
        // Running means the port takes connections, not just that tpws started:
        // a site check right after turning on must not race the bind.
        let port = command.port
        let plan = TPWSReadinessPlan.engine
        let runner = runner
        Task {
            for _ in 0..<plan.attempts {
                guard generation == gen, state == .starting, handle.isRunning else { return }
                if await runner.isReady(port: port) {
                    markRunning()
                    return
                }
                try? await Task.sleep(for: plan.interval)
            }
        }
    }

    func stop() {
        generation += 1
        if let handle, handle.isRunning {
            // tpws quits at once on SIGTERM; the bounded wait frees the port
            // for a restart.
            handle.stop()
            append(["tpws stopped"])
        }
        handle = nil
        startedAt = nil
        state = .stopped
    }

    func clearLog() {
        lines.removeAll()
    }

    private func markRunning() {
        state = .running
        startedAt = .now
    }

    private func receive(_ text: [String], generation gen: Int) {
        guard gen == generation else { return }
        append(text)
    }

    private func append(_ text: [String]) {
        for line in text where !line.isEmpty {
            let entry = LogLine(id: nextID, text: line)
            nextID += 1
            lines.append(entry)
            if entry.kind == .connection { connections += 1 }
            if let host = entry.host {
                hostsSeen.insert(host)
                recentHosts.removeAll { $0 == host }
                recentHosts.insert(host, at: 0)
                if recentHosts.count > 12 { recentHosts.removeLast() }
            }
        }
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    private func ended(code: Int32, generation gen: Int) {
        guard gen == generation else { return }
        handle = nil
        startedAt = nil
        let lastError = lines.last(where: { $0.kind == .error })?.text
        let reason = lastError ?? String(localized: "tpws quit with code \(Int(code)).")
        // Restart once; a second exit within a minute is a real failure.
        if let lastCommand, restarts.shouldRestart() {
            autoRestarts += 1
            append(["tpws quit by itself (\(reason)). Restarting it."])
            start(lastCommand)
            return
        }
        state = .failed(reason)
        onFailure?(reason)
    }

    // MARK: - One-off runs

    /// Runs `tpws --dry-run <args>`: tpws checks the flags and quits.
    nonisolated static func dryRun(_ arguments: [String]) async -> (ok: Bool, output: String) {
        await run(["--dry-run", "--socks", "--port=1"] + arguments)
    }

    nonisolated static func version() async -> String {
        let result = await run(["--version"])
        return result.output.split(whereSeparator: \.isNewline).first.map(String.init) ?? "unknown"
    }

    nonisolated private static func run(_ arguments: [String]) async -> (ok: Bool, output: String) {
        await LocalTPWSRunner().run(arguments)
    }
}
