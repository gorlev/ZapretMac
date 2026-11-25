import Foundation
import Observation
import ServiceManagement
import ZapretMacKit

/// The root helper for Transparent mode (S-080): its install state through
/// SMAppService, and an XPC connection to it. Registering needs the person's
/// approval in System Settings > Login Items; test runs never register.
@Observable
final class HelperClient {
    static let shared = HelperClient()

    enum State: Equatable {
        case notInstalled, needsApproval, ready, notFound
    }

    private(set) var state: State = .notInstalled
    /// The helper's protocol version, once it answered.
    private(set) var helperVersion: Int?
    /// The last error from install, remove, or the connection.
    var message: String?

    private var service: SMAppService { SMAppService.daemon(plistName: HelperInfo.plistName) }

    init() { refresh() }

    /// Reads the state from the system. Never changes it.
    func refresh() {
        state = testState ?? Self.state(for: service.status)
        if state != .ready { helperVersion = nil }
    }

    static func state(for status: SMAppService.Status) -> State {
        switch status {
        case .notRegistered: .notInstalled
        case .requiresApproval: .needsApproval
        case .enabled: .ready
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    var stateTitle: String {
        switch state {
        // SMAppService says "not found" for a daemon that was never registered, too.
        case .notInstalled, .notFound: String(localized: "Not installed")
        case .needsApproval: String(localized: "Needs approval in Login Items")
        case .ready: String(localized: "Ready")
        }
    }

    var isRegistered: Bool { state == .ready || state == .needsApproval }

    func register() {
        // Test, seed, and snapshot runs never change the system.
        guard !Store.isOverridden else { message = String(localized: "Test runs do not install the helper."); return }
        do {
            try service.register()
            message = nil
        } catch {
            message = error.localizedDescription
        }
        refresh()
        // A new registration waits for approval: show the person where.
        if state == .needsApproval { openSystemSettingsLoginItems() }
    }

    func unregister() async {
        guard !Store.isOverridden else { return }
        do {
            try await service.unregister()
            message = nil
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Asks the running helper for its protocol version. Nil when it does not answer.
    func checkVersion() async {
        guard state == .ready else { helperVersion = nil; return }
        helperVersion = await Self.call { proxy, done in
            proxy.version { done($0) }
        }
        if helperVersion == nil { message = String(localized: "The helper is installed but does not answer.") }
    }

    /// One XPC call with a 3-second limit. The connection is closed afterwards.
    nonisolated static func call<T: Sendable>(
        _ body: @escaping @Sendable (ZapretHelperProtocol, @escaping @Sendable (T) -> Void) -> Void
    ) async -> T? {
        let connection = makeConnection()
        connection.resume()
        defer { connection.invalidate() }
        return await call(on: connection, limit: 3, body)
    }

    nonisolated static func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: HelperInfo.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ZapretHelperProtocol.self)
        return connection
    }

    /// One XPC call on an open connection, waiting at most `limit` seconds.
    nonisolated static func call<T: Sendable>(
        on connection: NSXPCConnection, limit: TimeInterval,
        _ body: @escaping @Sendable (ZapretHelperProtocol, @escaping @Sendable (T) -> Void) -> Void
    ) async -> T? {
        let once = Once<T?>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.finish(nil) }
            guard let helper = proxy as? ZapretHelperProtocol else { once.finish(nil); return }
            body(helper) { once.finish($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + limit) { once.finish(nil) }
        }
    }

    // MARK: - Transparent mode (S-081)

    /// Who the app's Transparent mode calls: the real helper, or a fake one in
    /// self-test and snapshot runs.
    private(set) var caller: any HelperCalling = HelperXPC.shared
    /// A state set by a test run, kept by `refresh()`.
    private var testState: State?

    /// Self-test and snapshot runs only: talk to `fake`, and report `state`.
    func useFake(_ fake: any HelperCalling, state: State) {
        guard Store.isOverridden else { return }
        caller = fake
        setTestState(state)
    }

    /// Self-test and snapshot runs only: the helper "is" in `state` now.
    func setTestState(_ state: State) {
        guard Store.isOverridden else { return }
        testState = state
        self.state = state
    }
}

/// Talks to the real root helper over XPC. The connection that starts
/// Transparent mode stays open while it runs: the helper turns Transparent
/// mode off by itself when that connection drops (the app quit or crashed).
/// Test runs (APP_STORE set) never call the helper.
nonisolated final class HelperXPC: HelperCalling, @unchecked Sendable {
    static let shared = HelperXPC()

    private let lock = NSLock()
    /// The connection that started tpws, open until it is stopped.
    private var session: NSXPCConnection?
    private var connectionLost: (@Sendable () -> Void)?

    private var isTestRun: Bool { !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty }
    private static let testRefusal = "Test runs never call the helper."

    func setConnectionLost(_ handler: (@Sendable () -> Void)?) {
        lock.withLock { connectionLost = handler }
    }

    func startTransparent(port: Int, arguments: [String]) async -> String? {
        guard !isTestRun else { return Self.testRefusal }
        let connection = HelperClient.makeConnection()
        let id = ObjectIdentifier(connection)
        let lost: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            // Only the open session counts; closing it on purpose clears it first.
            let handler = self.lock.withLock { () -> (@Sendable () -> Void)? in
                guard let session = self.session, ObjectIdentifier(session) == id else { return nil }
                self.session = nil
                return self.connectionLost
            }
            handler?()
        }
        connection.invalidationHandler = lost
        connection.interruptionHandler = lost
        connection.resume()
        let reply: String?? = await HelperClient.call(on: connection, limit: HelperTPWSRunner.startLimit) { helper, done in
            helper.startTransparent(port: port, arguments: arguments) { done($0) }
        }
        guard case .some(.none) = reply else {
            connection.invalidate()
            return reply ?? String(localized: "The helper did not answer.")
        }
        // The old session ends only now, when the helper already belongs to the new one.
        let old = lock.withLock { () -> NSXPCConnection? in
            defer { session = connection }
            return session
        }
        old?.invalidate()
        return nil
    }

    func stopTransparent() async -> String? {
        guard !isTestRun else { return Self.testRefusal }
        let connection = lock.withLock { () -> NSXPCConnection? in
            defer { session = nil }
            return session
        }
        guard let connection else { return await cleanUp() }
        // Wait for the reply before closing, so the helper never sees the
        // connection drop while it still runs tpws for it.
        let reply: String?? = await HelperClient.call(on: connection, limit: HelperTPWSRunner.stopLimit) { helper, done in
            helper.stopTransparent { done($0) }
        }
        connection.invalidate()
        return reply ?? String(localized: "The helper did not answer.")
    }

    func status() async -> HelperStatus? {
        guard !isTestRun else { return nil }
        let body: @Sendable (ZapretHelperProtocol, @escaping @Sendable (HelperStatus) -> Void) -> Void = { helper, done in
            helper.status { running, port, pf, pid in
                done(HelperStatus(running: running, port: port, pfTokenPresent: pf, tpwsPID: pid))
            }
        }
        if let connection = lock.withLock({ session }) {
            return await HelperClient.call(on: connection, limit: 3, body)
        }
        return await HelperClient.call(body)
    }

    func cleanUp() async -> String? {
        guard !isTestRun else { return Self.testRefusal }
        let reply: String?? = await HelperClient.call { helper, done in
            helper.cleanUp { done($0) }
        }
        return reply ?? String(localized: "The helper did not answer.")
    }
}

/// Resumes a continuation exactly once, from whichever reply comes first.
nonisolated private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    func set(_ continuation: CheckedContinuation<T, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func finish(_ value: T) {
        let pending = lock.withLock { () -> CheckedContinuation<T, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
