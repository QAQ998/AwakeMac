import ServiceManagement
import XCTest
@testable import AwakeMac

@MainActor
final class LidModeConcurrencyTests: XCTestCase {
    func testConcurrentLidRequestsOnlyReachHelperOnce() async {
        let suite = "AwakeMacTests.\(UUID().uuidString)"
        let helper = ConcurrencyTestPowerHelper()
        let controller = WakeController(
            store: AwakeMac.SharedStateStore(suiteName: suite),
            helperClient: helper,
            helperInstaller: ConcurrencyTestInstaller(),
            loginItemService: ConcurrencyTestLoginItemService(),
            preferences: UserDefaults(suiteName: suite)!,
            detector: AwakeMac.HardwareCapabilityDetector(
                propertyReader: { key in
                    key == "AppleClamshellState" ? false : true
                },
                modelIdentifier: { "MacBookPro-Test" }
            )
        )
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        controller.startWake(duration: AwakeMac.WakeDuration.oneHour)

        let requests = (1...30).map { _ in
            Task { await controller.requestLidMode() }
        }
        var results: [Bool] = []
        for request in requests {
            results.append(await request.value)
        }

        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertEqual(results.filter { !$0 }.count, 29)
        XCTAssertEqual(helper.enableCount, 1)
        XCTAssertTrue(controller.state.isLidModeEnabled)
        controller.disableLidMode()
    }
}

@MainActor
private final class ConcurrencyTestPowerHelper: PowerHelperServicing {
    private(set) var enableCount = 0

    func enable(leaseID: String, deadline: Date?) async throws {
        enableCount += 1
        try? await Task.sleep(for: .milliseconds(120))
    }

    func renew(leaseID: String) async -> Bool { true }
    func disable() async throws {}
    func status() async -> (enabled: Bool, leaseExpiresAt: Date?) { (false, nil) }
}

private struct ConcurrencyTestInstaller: LocalPowerHelperInstalling {
    func status() -> LocalPowerHelperStatus { .installed }
    func install() async throws {}
    func uninstall() async throws {}
}

@MainActor
private final class ConcurrencyTestLoginItemService: LoginItemServicing {
    var status = SMAppService.Status.enabled

    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}
