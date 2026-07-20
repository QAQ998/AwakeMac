import ServiceManagement
import XCTest
@testable import AwakeMac

@MainActor
final class LoginItemServiceTests: XCTestCase {
    func testEnablingRegistersWhenServiceStatusIsNotFound() {
        let service = FakeLoginItemService(status: .notFound)
        let controller = WakeController(loginItemService: service)

        controller.setLoginItemEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertTrue(controller.loginItemEnabled)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status
    private(set) var registerCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        status = .notRegistered
    }

    func openSystemSettings() {}
}
