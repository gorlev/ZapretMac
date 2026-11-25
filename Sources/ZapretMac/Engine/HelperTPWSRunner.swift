import Foundation
import Synchronization
import ZapretMacKit

/// The helper's XPC calls, as the app uses them (S-081). `HelperXPC` talks to
/// the real root helper; the self-test and snapshots use `FakeHelperClient`.
/// String results are error messages, nil on success.
nonisolated protocol HelperCalling: AnyObject, Sendable {
    /// Starts tpws as root with pf rules. The connection that started it stays
    /// open until `stopTransparent`: when it drops, the helper cleans up.
    func startTransparent(port: Int, arguments: [String]) async -> String?
    func stopTransparent() async -> String?
    /// Nil when the helper does not answer.
    func status() async -> HelperStatus?
    /// Removes the anchor, releases pf, and stops tpws. Safe to call any time.
    func cleanUp() async -> String?
    /// Called once when the connection that started tpws ends by itself.
    func setConnectionLost(_ handler: (@Sendable () -> Void)?)
}

/// Runs tpws through the root helper in Transparent mode. One-shot runs
/// (--dry-run, --version) never need root and stay local.
nonisolated struct HelperTPWSRunner: TPWSRunner {
    let caller: any HelperCalling
    /// The longest wait for the helper to start tpws (it waits up to 5 s for the port, then runs pfctl).
    static let startLimit: TimeInterval = 12
    /// The longest wait for the helper to stop tpws, like `TPWSStopPolicy.standard` plus pfctl.
    static let stopLimit: TimeInterval = 5
    /// How often a running handle asks the helper whether tpws still runs.
    static let watchInterval: Duration = .seconds(3)

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    var binaryPath: String { LocalTPWSRunner().binaryPath }
    var isAvailable: Bool { LocalTPWSRunner().isAvailable }

    func start(_ command: TPWSCommand,
               output: (@Sendable ([String]) -> Void)?,
               exit: (@Sendable (Int32) -> Void)?) throws -> any TPWSHandle {
        let caller = caller
        let port = command.port
        let arguments = command.arguments
        // Engine.start is synchronous; the helper answers on an XPC queue, so
        // waiting here cannot deadlock. The wait is bounded.
        let reply = Self.wait(Self.startLimit) { await caller.startTransparent(port: port, arguments: arguments) }
        switch reply {
        case .none:
            throw Failure(message: String(localized: "The helper did not answer."))
        case .some(.some(let message)):
            throw Failure(message: message)
        case .some(.none):
            break
        }
        let handle = HelperTPWSHandle(caller: caller, exit: exit)
        output?([String(localized: "Transparent mode: tpws runs as root in ZapretMac's helper, so its output is not shown here.")])
        caller.setConnectionLost { [weak handle] in handle?.ended(code: 1) }
        handle.watch()
        return handle
    }

    func isReady(port: Int) async -> Bool {
        await Task.detached { LocalTPWSRunner.isListening(port) }.value
    }

    func run(_ arguments: [String]) async -> (ok: Bool, output: String) {
        await LocalTPWSRunner().run(arguments)
    }

    /// Runs `body` and waits for it at most `limit` seconds. Nil when it took longer.
    static func wait<T: Sendable>(_ limit: TimeInterval, _ body: @escaping @Sendable () async -> T) -> T? {
        let result = Mutex<T?>(nil)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let value = await body()
            result.withLock { $0 = value }
            done.signal()
        }
        _ = done.wait(timeout: .now() + limit)
        return result.withLock { $0 }
    }
}

/// tpws running in the helper. Its process is root's, so the pid comes from
/// the helper's status and stopping goes through the helper.
nonisolated final class HelperTPWSHandle: TPWSHandle {
    private let caller: any HelperCalling
    private let exit: (@Sendable (Int32) -> Void)?
    private let state = Mutex<(running: Bool, pid: Int32?)>((true, nil))

    init(caller: any HelperCalling, exit: (@Sendable (Int32) -> Void)?) {
        self.caller = caller
        self.exit = exit
    }

    var pid: Int32? { state.withLock { $0.pid } }
    var isRunning: Bool { state.withLock { $0.running } }

    /// Reads the pid, then asks every few seconds whether tpws still runs:
    /// the helper does not call back when it ends.
    func watch() {
        let caller = caller
        Task.detached { [weak self] in
            while let self, self.isRunning {
                if let status = await caller.status() {
                    if status.running {
                        self.state.withLock { $0.pid = status.tpwsPID > 0 ? status.tpwsPID : nil }
                    } else if self.isRunning {
                        self.ended(code: 1)
                        return
                    }
                }
                try? await Task.sleep(for: HelperTPWSRunner.watchInterval)
            }
        }
    }

    /// tpws or the helper went away by itself.
    func ended(code: Int32) {
        let was = state.withLock { value in
            defer { value.running = false }
            return value.running
        }
        if was { exit?(code) }
    }

    func terminate() {
        let caller = caller
        let was = markStopped()
        guard was else { return }
        Task.detached { _ = await caller.stopTransparent() }
    }

    /// Bounded: waits for the helper at most `HelperTPWSRunner.stopLimit`.
    func stop() {
        let caller = caller
        markStopped()
        _ = HelperTPWSRunner.wait(HelperTPWSRunner.stopLimit) { await caller.stopTransparent() }
    }

    @discardableResult
    private func markStopped() -> Bool {
        caller.setConnectionLost(nil)
        return state.withLock { value in
            defer { value.running = false }
            return value.running
        }
    }
}
