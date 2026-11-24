import Foundation
import Observation
import ZapretMacKit

/// Runs the bundled tpws binary in SOCKS mode and collects its output.
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
    var pid: Int32? { process?.processIdentifier }

    var isOn: Bool { state == .running || state == .starting }

    private var process: Process?
    private var nextID = 0
    /// Bumped on every start and stop, so output and exits from an old
    /// process never change the state of a new one.
    private var generation = 0
    private var lastCommand: TPWSCommand?
    private var recentCrashes: [Date] = []
    static let maxLines = 4000

    /// Contents/Helpers/tpws inside the app. TPWS_PATH overrides it.
    nonisolated static var binaryURL: URL {
        if let path = ProcessInfo.processInfo.environment["TPWS_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.bundleURL.appending(path: "Contents/Helpers/tpws")
    }

    static var binaryExists: Bool { FileManager.default.isExecutableFile(atPath: binaryURL.path) }

    func start(_ command: TPWSCommand) {
        stop()
        guard Self.binaryExists else {
            state = .failed("tpws is missing from the app. Rebuild it with ./build.sh.")
            return
        }
        generation += 1
        let gen = generation
        lastCommand = command
        connections = 0
        commandLine = command.commandLine(binary: Self.binaryURL.path)
        append(["$ " + commandLine])

        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = command.arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let reader = LineReader { [weak self] text in
            Task { @MainActor in self?.receive(text, generation: gen) }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { reader.feed(data) }
        }
        process.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            Task { @MainActor in self?.ended(code: code, generation: gen) }
        }
        do {
            try process.run()
        } catch {
            state = .failed("Could not start tpws: \(error.localizedDescription)")
            return
        }
        self.process = process
        state = .starting
        // tpws prints nothing on success in quiet mode: still running after a
        // moment means the port is bound and it is ready.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if generation == gen, state == .starting, process.isRunning { markRunning() }
        }
    }

    func stop() {
        generation += 1
        if let process, process.isRunning {
            process.terminate()
            // tpws quits at once on SIGTERM; wait briefly so the port is free
            // for a restart.
            let deadline = Date.now.addingTimeInterval(1.5)
            while process.isRunning, Date.now < deadline { usleep(20_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            append(["tpws stopped"])
        }
        process = nil
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
        if state == .starting, text.contains(where: { $0.contains("socks mode") || $0.contains("Running as") }) {
            markRunning()
        }
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
        process = nil
        startedAt = nil
        let lastError = lines.last(where: { $0.kind == .error })?.text
        let reason = lastError ?? "tpws quit with code \(code)."
        // Restart once; a second exit within a minute is a real failure.
        recentCrashes = recentCrashes.filter { $0 > Date.now.addingTimeInterval(-60) }
        if recentCrashes.isEmpty, let lastCommand {
            recentCrashes.append(.now)
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
        await Task.detached {
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { return (false, error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
        }.value
    }
}

/// Collects bytes from a pipe and hands out whole lines.
nonisolated final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    private let emit: @Sendable ([String]) -> Void

    init(emit: @escaping @Sendable ([String]) -> Void) {
        self.emit = emit
    }

    func feed(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var out: [String] = []
        while let newline = buffer.firstIndex(of: 10) {
            out.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        lock.unlock()
        if !out.isEmpty { emit(out) }
    }
}
