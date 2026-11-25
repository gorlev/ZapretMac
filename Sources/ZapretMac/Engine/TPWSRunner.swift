import Darwin
import Foundation
import ZapretMacKit

/// One tpws started by a runner.
nonisolated protocol TPWSHandle: AnyObject, Sendable {
    /// The process id, when the process runs on this side (nil for a remote one).
    var pid: Int32? { get }
    var isRunning: Bool { get }
    /// Asks tpws to quit (SIGTERM) without waiting.
    func terminate()
    /// Stops tpws with a bounded wait: SIGTERM, up to `TPWSStopPolicy.standard.grace`,
    /// then SIGKILL. Blocks until tpws is gone or killed.
    func stop()
}

/// The one place that knows how to run tpws: start, stop, readiness, one-shot runs.
/// `LocalTPWSRunner` runs the bundled binary as the user; a runner that goes through
/// a privileged helper can take its place in `Engine` without changing its logic.
nonisolated protocol TPWSRunner: Sendable {
    /// The tpws path shown in the command line.
    var binaryPath: String { get }
    /// False when tpws cannot be run at all (the binary is missing).
    var isAvailable: Bool { get }
    /// Starts tpws with `command`. Whole output lines go to `output` (nil throws the
    /// output away); `exit` gets the exit code. Both are called on any thread.
    func start(_ command: TPWSCommand,
               output: (@Sendable ([String]) -> Void)?,
               exit: (@Sendable (Int32) -> Void)?) throws -> any TPWSHandle
    /// True when 127.0.0.1:`port` accepts a connection.
    func isReady(port: Int) async -> Bool
    /// Runs tpws to the end (for --dry-run or --version) and returns its output.
    func run(_ arguments: [String]) async -> (ok: Bool, output: String)
}

/// Runs the bundled tpws as a child process of the app.
nonisolated struct LocalTPWSRunner: TPWSRunner {
    /// Contents/Helpers/tpws inside the app. TPWS_PATH overrides it.
    static var binaryURL: URL {
        if let path = ProcessInfo.processInfo.environment["TPWS_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.bundleURL.appending(path: "Contents/Helpers/tpws")
    }

    var binaryPath: String { Self.binaryURL.path }
    var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: binaryPath) }

    func start(_ command: TPWSCommand,
               output: (@Sendable ([String]) -> Void)?,
               exit: (@Sendable (Int32) -> Void)?) throws -> any TPWSHandle {
        if let pidFile = command.pidFile { Self.stopLeftover(pidFile: pidFile) }
        let process = Process()
        process.executableURL = Self.binaryURL
        process.arguments = command.arguments
        if let output {
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let reader = LineReader(emit: output)
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil } else { reader.feed(data) }
            }
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        if let exit {
            process.terminationHandler = { proc in exit(proc.terminationStatus) }
        }
        try process.run()
        return LocalTPWSHandle(process)
    }

    func isReady(port: Int) async -> Bool {
        await Task.detached { Self.isListening(port) }.value
    }

    func run(_ arguments: [String]) async -> (ok: Bool, output: String) {
        await Task.detached {
            let process = Process()
            process.executableURL = Self.binaryURL
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

    /// A tpws from an earlier run that was force-quit keeps the port busy.
    /// Its pid file names it; stop it if that process is still our tpws.
    static func stopLeftover(pidFile: String) {
        guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return }
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == binaryURL.path else { return }
        let policy = TPWSStopPolicy.leftover
        kill(pid, SIGTERM)
        for _ in 0..<policy.checks where kill(pid, 0) == 0 { usleep(policy.intervalMicroseconds) }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(atPath: pidFile)
    }

    static func isListening(_ port: Int) -> Bool {
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

/// A tpws child process.
nonisolated final class LocalTPWSHandle: TPWSHandle, @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    var pid: Int32? { process.processIdentifier }
    var isRunning: Bool { process.isRunning }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func stop() {
        let policy = TPWSStopPolicy.standard
        process.terminate()
        // Never wait forever for tpws to quit: a stuck one is killed.
        let deadline = Date.now.addingTimeInterval(policy.grace)
        while process.isRunning, Date.now < deadline { usleep(policy.intervalMicroseconds) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
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
