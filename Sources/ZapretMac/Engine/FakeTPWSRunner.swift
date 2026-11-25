import Foundation
import Synchronization
import ZapretMacKit

/// A tpws that is never started, for the self-test: it says what it was asked to
/// do, and the test makes it print lines or quit with an exit code.
nonisolated final class FakeTPWSRunner: TPWSRunner {
    /// One fake tpws.
    nonisolated final class Handle: TPWSHandle {
        let command: TPWSCommand
        private let output: (@Sendable ([String]) -> Void)?
        private let exit: (@Sendable (Int32) -> Void)?
        private let running = Mutex(true)
        private let stops = Mutex(0)

        init(command: TPWSCommand, output: (@Sendable ([String]) -> Void)?, exit: (@Sendable (Int32) -> Void)?) {
            self.command = command
            self.output = output
            self.exit = exit
        }

        var pid: Int32? { nil }
        var isRunning: Bool { running.withLock { $0 } }
        /// How many times the engine stopped it.
        var stopCount: Int { stops.withLock { $0 } }

        /// Prints lines, as tpws does on stdout and stderr.
        func print(_ lines: [String]) { output?(lines) }

        /// Quits by itself with `code`.
        func quit(code: Int32) {
            running.withLock { $0 = false }
            exit?(code)
        }

        func terminate() { stop() }

        /// Stopping a real tpws ends it with SIGTERM; its exit still arrives.
        func stop() {
            let wasRunning = running.withLock { value in
                defer { value = false }
                return value
            }
            stops.withLock { $0 += 1 }
            if wasRunning { exit?(15) }
        }
    }

    private let state = Mutex<(handles: [Handle], ready: Bool)>(([], true))

    init() {}

    var binaryPath: String { "/fake/tpws" }
    var isAvailable: Bool { true }

    /// Every fake tpws started so far, oldest first.
    var handles: [Handle] { state.withLock { $0.handles } }
    var latest: Handle? { handles.last }
    /// Whether the port "accepts connections".
    var ready: Bool {
        get { state.withLock { $0.ready } }
        set { state.withLock { $0.ready = newValue } }
    }

    func start(_ command: TPWSCommand,
               output: (@Sendable ([String]) -> Void)?,
               exit: (@Sendable (Int32) -> Void)?) throws -> any TPWSHandle {
        let handle = Handle(command: command, output: output, exit: exit)
        state.withLock { $0.handles.append(handle) }
        return handle
    }

    func isReady(port: Int) async -> Bool { ready }

    func run(_ arguments: [String]) async -> (ok: Bool, output: String) { (true, "") }
}
