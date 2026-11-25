import Foundation
import Network
import ZapretMacKit

/// A tiny HTTP server on 127.0.0.1 that hands macOS the PAC file:
/// `GET /proxy.pac` answers with the script, anything else is a 404.
nonisolated final class PACServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ZapretMac.PACServer")
    private let lock = NSLock()
    private var listener: NWListener?
    private var body = Data()
    private var boundPort: UInt16?

    /// The PAC file's address while the server runs.
    var url: URL? {
        lock.withLock { boundPort }.flatMap { URL(string: "http://127.0.0.1:\($0)\(PACFile.path)") }
    }

    var isRunning: Bool { url != nil }

    /// Replaces the script the server hands out.
    func update(_ script: String) {
        lock.withLock { body = Data(script.utf8) }
    }

    /// Starts on `preferredPort`, or on any free port when that one is taken.
    /// Returns the PAC file's address, or nil when no port works. A running
    /// server keeps its address and only takes the new script.
    func start(preferredPort: Int, script: String) async -> URL? {
        update(script)
        if let url { return url }
        if (1...65535).contains(preferredPort), let port = await listen(on: UInt16(preferredPort)) {
            return set(port)
        }
        if let port = await listen(on: 0) { return set(port) }
        return nil
    }

    func stop() {
        lock.withLock {
            listener?.cancel()
            listener = nil
            boundPort = nil
        }
    }

    private func set(_ port: UInt16) -> URL? {
        lock.withLock { boundPort = port }
        return url
    }

    /// Listens on 127.0.0.1 only. Returns the bound port once ready.
    private func listen(on port: UInt16) async -> UInt16? {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        guard let listener = try? NWListener(using: parameters) else { return nil }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        let ready: Bool = await withCheckedContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { continuation.resume(returning: true) }
                case .failed, .cancelled: once.run { continuation.resume(returning: false) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
        guard ready, let bound = listener.port?.rawValue else {
            listener.cancel()
            return nil
        }
        listener.stateUpdateHandler = nil
        lock.withLock { self.listener = listener }
        return bound
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    /// Reads up to the end of the request headers, answers, and closes.
    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            let headersDone = buffer.range(of: Data("\r\n\r\n".utf8)) != nil || buffer.range(of: Data("\n\n".utf8)) != nil
            if headersDone || isComplete || error != nil || buffer.count > 16_384 {
                let response = self.response(to: buffer)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func response(to request: Data) -> Data {
        let line = String(decoding: request.prefix(while: { $0 != 0x0A && $0 != 0x0D }), as: UTF8.self)
        let parts = line.split(separator: " ")
        let method = parts.first.map(String.init) ?? ""
        let target = parts.count > 1 ? String(parts[1]) : ""
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        guard method == "GET" || method == "HEAD", path == PACFile.path else {
            return Self.http(status: "404 Not Found", type: "text/plain; charset=utf-8", body: Data("Not found\n".utf8), head: method == "HEAD")
        }
        return Self.http(status: "200 OK", type: PACFile.contentType, body: lock.withLock { body }, head: method == "HEAD")
    }

    private static func http(status: String, type: String, body: Data, head: Bool) -> Data {
        var data = Data("""
        HTTP/1.1 \(status)\r
        Content-Type: \(type)\r
        Content-Length: \(body.count)\r
        Cache-Control: no-cache\r
        Connection: close\r
        \r

        """.utf8)
        if !head { data.append(body) }
        return data
    }
}

/// Runs a closure once, for continuations resumed from several callbacks.
private nonisolated final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        let first = lock.withLock { () -> Bool in
            defer { done = true }
            return !done
        }
        if first { body() }
    }
}
