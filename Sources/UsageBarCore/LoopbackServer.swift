import Foundation
import Network

/// One-shot HTTP listener on the loopback interface that waits for an OAuth
/// redirect and returns its query parameters.
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let requestedPort: UInt16
    private let callbackPath: String
    private let queue = DispatchQueue(label: "UsageBar.LoopbackServer")

    // Guarded by `queue`.
    private var result: Result<[String: String], Error>?
    private var waiter: CheckedContinuation<[String: String], Error>?
    private var startFinished = false

    init(port: UInt16, callbackPath: String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        let endpointPort = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: port)!
        do {
            listener = try NWListener(using: parameters, on: endpointPort)
        } catch {
            throw UsageError.portInUse(port)
        }
        requestedPort = port
        self.callbackPath = callbackPath
    }

    /// Starts listening and returns the bound port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            // Runs on `queue`, so `startFinished` needs no extra locking.
            listener.stateUpdateHandler = { [self] state in
                guard !startFinished else { return }
                switch state {
                case .ready:
                    startFinished = true
                    continuation.resume(returning: listener.port?.rawValue ?? requestedPort)
                case .failed, .waiting:
                    startFinished = true
                    listener.cancel()
                    continuation.resume(throwing: UsageError.portInUse(requestedPort))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
        }
    }

    /// Waits for the redirect. Throws `signInTimedOut` after `timeout`, or
    /// `CancellationError` if the calling task is cancelled.
    func waitForCallback(timeout: Duration) async throws -> [String: String] {
        let timer = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.finish(.failure(UsageError.signInTimedOut))
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if let result = self.result {
                        continuation.resume(with: result)
                    } else {
                        self.waiter = continuation
                    }
                }
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    func stop() {
        listener.cancel()
    }

    private func finish(_ result: Result<[String: String], Error>) {
        queue.async {
            guard self.result == nil else { return }
            self.result = result
            self.waiter?.resume(with: result)
            self.waiter = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let target = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let components = URLComponents(string: "http://localhost" + target)

            guard let components, components.path == self.callbackPath else {
                self.respond(connection, status: "404 Not Found", body: "Not found")
                return
            }
            var params: [String: String] = [:]
            for item in components.queryItems ?? [] { params[item.name] = item.value ?? "" }

            let ok = params["code"] != nil
            self.respond(connection, status: "200 OK", body: Self.page(success: ok))
            self.finish(.success(params))
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func page(success: Bool) -> String {
        let message = success ? "Signed in. You can close this tab and go back to UsageBar." : "Sign-in did not complete. Go back to UsageBar and try again."
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>UsageBar</title>
        <style>body{font:16px -apple-system,sans-serif;display:flex;height:90vh;align-items:center;justify-content:center;background:#f7f7f5;color:#222}
        @media (prefers-color-scheme: dark){body{background:#1b1b1d;color:#eee}}</style></head>
        <body><p>\(message)</p></body></html>
        """
    }
}
