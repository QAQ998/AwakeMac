import Foundation
import Security

enum LocalPowerHelperStatus: Equatable, Sendable {
    case notInstalled
    case updateRequired
    case installed
    case installing
    case unavailable
}

protocol LocalPowerHelperInstalling: Sendable {
    func status() -> LocalPowerHelperStatus
    func install() async throws
    func uninstall() async throws
}

struct LocalPowerHelperInstaller: LocalPowerHelperInstalling {
    private static let installedHelperURL = URL(
        fileURLWithPath: "/Library/PrivilegedHelperTools/com.zhuhai.AwakeMac.PowerHelper"
    )
    private static let installedPlistURL = URL(
        fileURLWithPath: "/Library/LaunchDaemons/com.zhuhai.AwakeMac.PowerHelper.plist"
    )
    private static let installedRequirementURL = URL(
        fileURLWithPath: "/Library/Application Support/AwakeMac/authorized-client.requirement"
    )

    func status() -> LocalPowerHelperStatus {
        guard let payload = try? payloadURLs() else { return .unavailable }

        let fileManager = FileManager.default
        let installedFilesExist = fileManager.fileExists(atPath: Self.installedHelperURL.path)
            && fileManager.fileExists(atPath: Self.installedPlistURL.path)
            && fileManager.fileExists(atPath: Self.installedRequirementURL.path)

        guard installedFilesExist else { return .notInstalled }

        let payloadMatches = fileManager.contentsEqual(
            atPath: payload.helper.path,
            andPath: Self.installedHelperURL.path
        ) && fileManager.contentsEqual(
            atPath: payload.plist.path,
            andPath: Self.installedPlistURL.path
        ) && installedRequirementMatchesCurrentApp()

        return payloadMatches ? .installed : .updateRequired
    }

    private func installedRequirementMatchesCurrentApp() -> Bool {
        guard let requirementText = try? String(
            contentsOf: Self.installedRequirementURL,
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines),
        !requirementText.isEmpty else { return false }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            [],
            &requirement
        ) == errSecSuccess, let requirement else { return false }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            [],
            &staticCode
        ) == errSecSuccess, let staticCode else { return false }

        return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
    }

    func install() async throws {
        try await runPrivileged(action: "install")
    }

    func uninstall() async throws {
        try await runPrivileged(action: "uninstall")
    }

    private func runPrivileged(action: String) async throws {
        let installerURL = try payloadURLs().installer

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e", "on run argv",
                "-e", "set installerPath to item 1 of argv",
                "-e", "set installerAction to item 2 of argv",
                "-e", "do shell script (\"/bin/zsh \" & quoted form of installerPath & \" \" & quoted form of installerAction) with administrator privileges",
                "-e", "end run",
                installerURL.path,
                action
            ]
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw LocalPowerHelperInstallerError.launchFailed(error.localizedDescription)
            }

            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)
                let outputText = String(data: outputData, encoding: .utf8)
                let message = [errorText, outputText]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                throw LocalPowerHelperInstallerError.operationFailed(message)
            }
        }.value
    }

    private func payloadURLs() throws -> (installer: URL, helper: URL, plist: URL) {
        let bundle = Bundle.main
        let installer = bundle.url(
            forResource: "install-local-helper",
            withExtension: "sh",
            subdirectory: "LocalHelper"
        ) ?? bundle.url(forResource: "install-local-helper", withExtension: "sh")
        let plist = bundle.url(
            forResource: "com.zhuhai.AwakeMac.PowerHelper.local",
            withExtension: "plist",
            subdirectory: "LocalHelper"
        ) ?? bundle.url(forResource: "com.zhuhai.AwakeMac.PowerHelper.local", withExtension: "plist")
        let helper = bundle.bundleURL
            .appending(path: "Contents/Library/LaunchDaemons/PowerHelper")

        guard let installer, let plist,
              FileManager.default.isExecutableFile(atPath: helper.path)
        else {
            throw LocalPowerHelperInstallerError.payloadMissing
        }

        return (installer, helper, plist)
    }
}

enum LocalPowerHelperInstallerError: LocalizedError {
    case payloadMissing
    case launchFailed(String)
    case operationFailed(String?)

    var errorDescription: String? {
        switch self {
        case .payloadMissing:
            "The local helper installer payload is missing."
        case .launchFailed(let message):
            "The local helper installer could not start: \(message)"
        case .operationFailed(let message):
            message ?? "The local helper installer failed."
        }
    }
}
