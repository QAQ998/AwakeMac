import Foundation

@MainActor
protocol PowerHelperServicing: AnyObject {
    func enable(leaseID: String, deadline: Date?) async throws
    func renew(leaseID: String) async -> Bool
    func disable() async throws
    func status() async -> (enabled: Bool, leaseExpiresAt: Date?)
}

@MainActor
final class PowerHelperClient: PowerHelperServicing {
    private var connection: NSXPCConnection?

    private func proxy() throws -> PowerHelperProtocol {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: powerHelperMachServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: PowerHelperProtocol.self)
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor [weak self] in self?.connection = nil }
            }
            connection.interruptionHandler = { [weak self] in
                Task { @MainActor [weak self] in self?.connection = nil }
            }
            connection.resume()
            self.connection = connection
        }

        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? PowerHelperProtocol else {
            throw HelperClientError.connectionUnavailable
        }
        return proxy
    }

    func enable(leaseID: String, deadline: Date?) async throws {
        let proxy = try proxy()
        try await withCheckedThrowingContinuation { continuation in
            proxy.enableLidMode(leaseID: leaseID, hardDeadline: deadline) { success, message in
                success ? continuation.resume() : continuation.resume(throwing: HelperClientError.operationFailed(message))
            }
        }
    }

    func renew(leaseID: String) async -> Bool {
        guard let proxy = try? proxy() else { return false }
        return await withCheckedContinuation { continuation in
            proxy.renewLease(leaseID: leaseID) { continuation.resume(returning: $0) }
        }
    }

    func disable() async throws {
        let proxy = try proxy()
        try await withCheckedThrowingContinuation { continuation in
            proxy.disableLidMode { success, message in
                success ? continuation.resume() : continuation.resume(throwing: HelperClientError.operationFailed(message))
            }
        }
    }

    func status() async -> (enabled: Bool, leaseExpiresAt: Date?) {
        guard let proxy = try? proxy() else { return (false, nil) }
        return await withCheckedContinuation { continuation in
            proxy.status { enabled, expiry in continuation.resume(returning: (enabled, expiry)) }
        }
    }
}

enum HelperClientError: LocalizedError {
    case connectionUnavailable
    case operationFailed(String?)

    var errorDescription: String? {
        switch self {
        case .connectionUnavailable: "The privileged helper is unavailable."
        case .operationFailed(let message): message ?? "The privileged helper operation failed."
        }
    }
}
