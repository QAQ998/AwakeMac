import AppKit
import Foundation
import Security

final class PowerHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = PowerHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard ClientValidator.isAllowed(connection: connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: PowerHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private enum ClientValidator {
    private static let localRequirementURL = URL(
        fileURLWithPath: "/Library/Application Support/AwakeMac/authorized-client.requirement"
    )

    static func isAllowed(connection: NSXPCConnection) -> Bool {
        guard
            let application = NSRunningApplication(processIdentifier: connection.processIdentifier),
            application.bundleIdentifier == "com.zhuhai.AwakeMac",
            let codePath = application.bundleURL as CFURL?
        else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(codePath, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        guard SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess else { return false }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let identifier = info[kSecCodeInfoIdentifier as String] as? String
        else { return false }

        guard identifier == "com.zhuhai.AwakeMac" else { return false }

        if let requirementText = try? String(contentsOf: localRequirementURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !requirementText.isEmpty {
            var requirement: SecRequirement?
            guard SecRequirementCreateWithString(
                requirementText as CFString,
                [],
                &requirement
            ) == errSecSuccess, let requirement else { return false }
            return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
        }

        let clientTeam = info[kSecCodeInfoTeamIdentifier as String] as? String
        if let helperTeam = helperTeamIdentifier() {
            return clientTeam == helperTeam
        }
        return false
    }

    private static func helperTeamIdentifier() -> String? {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]) as CFURL
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL, [], &code) == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any]
        else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

final class PowerHelperService: NSObject, PowerHelperProtocol, @unchecked Sendable {
    private struct Lease {
        let id: String
        var expiresAt: Date
        let hardDeadline: Date?
    }

    private let queue = DispatchQueue(label: "com.zhuhai.AwakeMac.PowerHelper.state")
    private let markerURL = URL(fileURLWithPath: "/var/db/com.zhuhai.AwakeMac.PowerHelper.state")
    private var lease: Lease?
    private var timer: DispatchSourceTimer?
    private let leaseInterval: TimeInterval = 90

    override init() {
        super.init()
        queue.sync {
            if FileManager.default.fileExists(atPath: markerURL.path) {
                _ = setSystemLidSleepDisabled(false)
                try? FileManager.default.removeItem(at: markerURL)
            }
            startWatchdog()
        }
    }

    func enableLidMode(leaseID: String, hardDeadline: Date?, reply: @escaping @Sendable (Bool, String?) -> Void) {
        queue.async {
            let expiry = self.nextExpiry(hardDeadline: hardDeadline)
            guard expiry > .now else {
                reply(false, "The requested wake deadline has already passed.")
                return
            }
            let result = self.setSystemLidSleepDisabled(true)
            guard result.success else {
                reply(false, result.message)
                return
            }
            self.lease = Lease(id: leaseID, expiresAt: expiry, hardDeadline: hardDeadline)
            try? Data(leaseID.utf8).write(to: self.markerURL, options: .atomic)
            reply(true, nil)
        }
    }

    func renewLease(leaseID: String, reply: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            guard var lease = self.lease, lease.id == leaseID else {
                reply(false)
                return
            }
            lease.expiresAt = self.nextExpiry(hardDeadline: lease.hardDeadline)
            guard lease.expiresAt > .now else {
                self.restoreDefaultSleep()
                reply(false)
                return
            }
            self.lease = lease
            reply(true)
        }
    }

    func disableLidMode(reply: @escaping @Sendable (Bool, String?) -> Void) {
        queue.async {
            let result = self.setSystemLidSleepDisabled(false)
            if result.success {
                self.lease = nil
                try? FileManager.default.removeItem(at: self.markerURL)
            }
            reply(result.success, result.message)
        }
    }

    func status(reply: @escaping @Sendable (Bool, Date?) -> Void) {
        queue.async {
            reply(self.lease != nil, self.lease?.expiresAt)
        }
    }

    private func nextExpiry(hardDeadline: Date?) -> Date {
        let leaseExpiry = Date.now.addingTimeInterval(leaseInterval)
        return hardDeadline.map { min($0, leaseExpiry) } ?? leaseExpiry
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, let lease = self.lease, lease.expiresAt <= .now else { return }
            self.restoreDefaultSleep()
        }
        timer.resume()
        self.timer = timer
    }

    private func restoreDefaultSleep() {
        _ = setSystemLidSleepDisabled(false)
        lease = nil
        try? FileManager.default.removeItem(at: markerURL)
    }

    private func setSystemLidSleepDisabled(_ disabled: Bool) -> (success: Bool, message: String?) {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (false, message?.isEmpty == false ? message : "pmset exited with status \(process.terminationStatus)")
        }
        return (true, nil)
    }
}
