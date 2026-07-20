import ServiceManagement
import XCTest
@testable import AwakeMac

@MainActor
final class WakeControllerNotificationTests: XCTestCase {
    func testThermalNotificationPostedOffMainActorDoesNotCrash() async {
        let suite = "AwakeMacTests.\(UUID().uuidString)"
        let store = AwakeMac.SharedStateStore(suiteName: suite)
        let preferences = UserDefaults(suiteName: suite)!
        let loginItem = NotificationTestLoginItemService()
        let controller = WakeController(
            store: store,
            loginItemService: loginItem,
            preferences: preferences
        )
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        controller.start()

        let posted = expectation(description: "Background notification posted")
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 1...20 {
                NotificationCenter.default.post(
                    name: ProcessInfo.thermalStateDidChangeNotification,
                    object: nil
                )
            }
            posted.fulfill()
        }

        await fulfillment(of: [posted], timeout: 2)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(controller.state.safetyStatus, AwakeMac.PowerSafetyStatus.normal)
    }

    func testDistributedNotificationPostedOffMainActorConsumesPendingAction() async {
        let suite = "AwakeMacTests.\(UUID().uuidString)"
        let store = AwakeMac.SharedStateStore(suiteName: suite)
        let preferences = UserDefaults(suiteName: suite)!
        let controller = WakeController(
            store: store,
            loginItemService: NotificationTestLoginItemService(),
            preferences: preferences
        )
        defer {
            controller.stopAll()
            UserDefaults().removePersistentDomain(forName: suite)
        }
        controller.start()
        store.writePendingAction(
            AwakeMac.PendingWakeAction(
                kind: .start,
                minutes: 30,
                hasExplicitDuration: true
            )
        )

        let posted = expectation(description: "Background distributed notification posted")
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 1...20 {
                DistributedNotificationCenter.default().post(
                    name: AwakeMac.SharedStateStore.distributedNotification,
                    object: nil
                )
            }
            posted.fulfill()
        }

        await fulfillment(of: [posted], timeout: 2)
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(controller.state.isAwakeEnabled)
        XCTAssertEqual(controller.state.selectedDuration, AwakeMac.WakeDuration.thirtyMinutes)
    }
}

@MainActor
private final class NotificationTestLoginItemService: LoginItemServicing {
    var status = SMAppService.Status.enabled

    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}
