import Darwin
import Foundation
import ZapretMacKit
import os

let log = Logger(subsystem: HelperInfo.machServiceName, category: "helper")

/// Runs tpws as root and puts the pf anchor in place, and undoes both.
/// Every method takes the lock, so XPC calls from any queue are safe.
final class Transparent: @unchecked Sendable {
    static let shared = Transparent()

    private let lock = NSLock()
    private var process: Process?
    private var port = 0
    private var token: String?
    private var owner: ObjectIdentifier?

    /// What tpws always gets from the helper, before the app's arguments.
    static func fixedArguments(port: Int) -> [String] {
        HelperInfo.fixedTPWSArguments(port: port)
    }

    func status() -> HelperStatus {
        lock.withLock {
            HelperStatus(running: process?.isRunning == true, port: port,
                         pfTokenPresent: token != nil, tpwsPID: process?.processIdentifier ?? 0)
        }
    }

    func start(port: Int, arguments: [String], home: String, owner: ObjectIdentifier) -> String? {
        guard (1024...65535).contains(port) else { return "bad port \(port)" }
        if let problem = HelperArguments.problem(in: arguments, allowedFolders: HelperArguments.allowedFolders(home: home)) {
            log.error("refused tpws arguments: \(problem, privacy: .public)")
            return "refused: \(problem)"
        }
        let tpws = Paths.tpws
        guard let team = Signing.teamID(), Signing.isSigned(tpws, identifier: "tpws", team: team) else {
            log.error("tpws at \(tpws.path, privacy: .public) is missing or not signed by our team")
            return "tpws is missing or not signed by ZapretMac's team"
        }
        _ = cleanUp(reason: "restart")

        return lock.withLock { () -> String? in
            let process = Process()
            process.executableURL = tpws
            process.arguments = Self.fixedArguments(port: port) + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] ended in
                // tpws died on its own: take the rules away, or the web would stop working.
                self?.tpwsEnded(ended)
            }
            do { try process.run() } catch {
                return "could not start tpws: \(error.localizedDescription)"
            }
            self.process = process
            self.port = port
            self.owner = owner

            // Rules only once tpws answers, so no connection is sent to a closed port.
            guard Self.waitForPort(port, process: process) else {
                stopLocked()
                return "tpws did not start listening on port \(port)"
            }
            if let error = Self.pfctl(["-a", HelperInfo.anchor, "-f", "-"], input: PFRules.anchorText(port: port)).error {
                stopLocked()
                return "pfctl could not load the rules: \(error)"
            }
            let enable = Self.pfctl(["-E"])
            guard let token = Self.token(in: enable.output) else {
                stopLocked()
                return "pfctl could not enable pf: \(enable.error ?? enable.output)"
            }
            self.token = token
            saveState()
            log.info("transparent mode on, port \(port), tpws \(process.processIdentifier)")
            return nil
        }
    }

    /// Flushes the anchor, releases pf, stops tpws. Idempotent.
    @discardableResult
    func cleanUp(reason: String) -> String? {
        lock.withLock {
            stopLocked()
            log.info("transparent mode off (\(reason, privacy: .public))")
            return nil
        }
    }

    /// The app's connection ended. If it turned Transparent mode on, turn it off.
    func ownerGone(_ id: ObjectIdentifier) {
        let mine = lock.withLock { owner == id && (process != nil || token != nil) }
        if mine { cleanUp(reason: "the app's connection ended") }
    }

    /// At launch: whatever a crashed helper left behind goes.
    func recoverAtLaunch() {
        _ = Self.pfctl(["-a", HelperInfo.anchor, "-F", "all"])
        if let data = try? Data(contentsOf: Paths.state),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            if let token = saved.token { _ = Self.pfctl(["-X", token]) }
            if saved.pid > 0, Self.executablePath(of: saved.pid) == Paths.tpws.path { kill(saved.pid, SIGTERM) }
        }
        try? FileManager.default.removeItem(at: Paths.state)
        log.info("flushed any leftover anchor at launch")
    }

    // MARK: - Locked helpers

    private func tpwsEnded(_ ended: Process) {
        let current = lock.withLock { process === ended }
        if current { cleanUp(reason: "tpws exited with \(ended.terminationStatus)") }
    }

    /// Call with the lock held.
    private func stopLocked() {
        _ = Self.pfctl(["-a", HelperInfo.anchor, "-F", "all"])
        if let token { _ = Self.pfctl(["-X", token]) }
        token = nil
        if let process {
            self.process = nil
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }
        port = 0
        owner = nil
        try? FileManager.default.removeItem(at: Paths.state)
    }

    private struct SavedState: Codable {
        var token: String?
        var pid: Int32
    }

    private func saveState() {
        let state = SavedState(token: token, pid: process?.processIdentifier ?? 0)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: Paths.state, options: .atomic) }
    }

    // MARK: - System calls

    private static func pfctl(_ arguments: [String], input: String? = nil) -> (output: String, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        let stdin = Pipe()
        process.standardInput = stdin
        do { try process.run() } catch { return ("", error.localizedDescription) }
        if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
        try? stdin.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return (text, process.terminationStatus == 0 ? nil : text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `pfctl -E` prints "Token : 1234567890".
    static func token(in output: String) -> String? {
        for line in output.split(separator: "\n") where line.hasPrefix("Token") {
            let value = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
            if !value.isEmpty, value.allSatisfy(\.isNumber) { return value }
        }
        return nil
    }

    private static func waitForPort(_ port: Int, process: Process) -> Bool {
        for _ in 0..<50 {
            guard process.isRunning else { return false }
            if accepts(port) { return true }
            usleep(100_000)
        }
        return false
    }

    private static func accepts(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
