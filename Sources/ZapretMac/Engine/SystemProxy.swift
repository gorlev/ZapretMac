import Foundation
import Observation
import ZapretMacKit

/// Points the Mac's SOCKS proxy (System Settings > Network > Proxies) at
/// tpws, and puts back what was there before. The previous settings are
/// saved, so a crash or forced quit is undone on the next launch.
@Observable
final class SystemProxy {
    private(set) var isApplied = false
    private(set) var isBusy = false
    private(set) var lastError: String?

    private let defaults: UserDefaults
    private let savedKey = "systemProxy.saved"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isApplied = defaults.data(forKey: savedKey) != nil
    }

    /// Previous SOCKS settings per network service, saved before applying.
    private var saved: [String: ProxyState]? {
        get { defaults.data(forKey: savedKey).flatMap { try? JSONDecoder().decode([String: ProxyState].self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: savedKey)
            } else {
                defaults.removeObject(forKey: savedKey)
            }
        }
    }

    func apply(port: Int) async {
        isBusy = true
        defer { isBusy = false }
        lastError = nil
        let services = await Self.services()
        guard !services.isEmpty else {
            lastError = "No active network service found."
            return
        }
        if saved == nil {
            var previous: [String: ProxyState] = [:]
            for service in services {
                previous[service] = await Self.state(of: service)
            }
            saved = previous
        }
        var commands: [[String]] = []
        for service in services {
            commands.append(["-setsocksfirewallproxy", service, "127.0.0.1", String(port)])
            commands.append(["-setsocksfirewallproxystate", service, "on"])
        }
        if let error = await Self.runAll(commands) {
            lastError = error
            saved = nil
            isApplied = false
        } else {
            isApplied = true
        }
    }

    func restore() async {
        guard let previous = saved else { isApplied = false; return }
        isBusy = true
        defer { isBusy = false }
        if let error = await Self.runAll(Self.restoreCommands(previous)) {
            lastError = error
        } else {
            saved = nil
            isApplied = false
        }
    }

    /// At quit: blocks until the proxy is back, without an admin prompt.
    func restoreNow() {
        guard let previous = saved else { return }
        for command in Self.restoreCommands(previous) { _ = Self.networksetup(command) }
        saved = nil
        isApplied = false
    }

    private static func restoreCommands(_ previous: [String: ProxyState]) -> [[String]] {
        var commands: [[String]] = []
        for (service, state) in previous.sorted(by: { $0.key < $1.key }) {
            if state.enabled, !state.server.isEmpty {
                commands.append(["-setsocksfirewallproxy", service, state.server, String(state.port)])
                commands.append(["-setsocksfirewallproxystate", service, "on"])
            } else {
                commands.append(["-setsocksfirewallproxystate", service, "off"])
            }
        }
        return commands
    }

    // MARK: - networksetup

    nonisolated static func services() async -> [String] {
        await Task.detached { ProxyState.services(fromList: networksetup(["-listallnetworkservices"]).output) }.value
    }

    nonisolated static func state(of service: String) async -> ProxyState {
        await Task.detached {
            ProxyState(networksetupOutput: networksetup(["-getsocksfirewallproxy", service]).output)
                ?? ProxyState(enabled: false, server: "", port: 0)
        }.value
    }

    /// Runs each command as the user. If macOS refuses, runs them all once
    /// more with one administrator prompt. Returns an error message, or nil.
    nonisolated private static func runAll(_ commands: [[String]]) async -> String? {
        await Task.detached {
            var refused = false
            for command in commands {
                let result = networksetup(command)
                if result.status != 0 || result.output.localizedCaseInsensitiveContains("error")
                    || result.output.localizedCaseInsensitiveContains("admin") {
                    refused = true
                    break
                }
            }
            guard refused else { return nil }
            let script = commands.map { command in
                (["/usr/sbin/networksetup"] + command).map(shellQuote).joined(separator: " ")
            }.joined(separator: " && ")
            let apple = "do shell script \"\(script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
            let result = run("/usr/bin/osascript", ["-e", apple])
            if result.status == 0 { return nil }
            return result.output.contains("-128") ? "Cancelled." : "Could not change the proxy: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }.value
    }

    nonisolated private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    nonisolated static func networksetup(_ arguments: [String]) -> (status: Int32, output: String) {
        run("/usr/sbin/networksetup", arguments)
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
