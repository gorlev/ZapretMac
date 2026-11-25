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
        state = Self.state(for: service.status)
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
        let connection = NSXPCConnection(machServiceName: HelperInfo.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ZapretHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let once = Once<T?>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.finish(nil) }
            guard let helper = proxy as? ZapretHelperProtocol else { once.finish(nil); return }
            body(helper) { once.finish($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { once.finish(nil) }
        }
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
