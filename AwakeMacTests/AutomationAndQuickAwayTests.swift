import ServiceManagement
import XCTest
@testable import AwakeMac

@MainActor
final class AutomationAndQuickAwayTests: XCTestCase {
    func testAppAutomationStartsAndStopsAfterConfiguredGrace() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.detector.isTargetRunning = true
        fixture.controller.configureAutomationTarget(bundleIdentifier: "com.example.Renderer", name: "Renderer")
        fixture.controller.setAppAutomationEnabled(true)

        XCTAssertTrue(fixture.controller.state.isAwakeEnabled)
        XCTAssertEqual(fixture.controller.state.sessionSource, .appAutomation)

        let exitTime = Date(timeIntervalSince1970: 10_000)
        fixture.detector.isTargetRunning = false
        fixture.controller.reconcileAppAutomation(now: exitTime)
        XCTAssertEqual(
            fixture.controller.state.appAutomationExitDeadline,
            exitTime.addingTimeInterval(600)
        )

        fixture.controller.reconcileAppAutomation(now: exitTime.addingTimeInterval(601))
        XCTAssertFalse(fixture.controller.state.isAwakeEnabled)
    }

    func testRelaunchDuringGraceCancelsAutomaticStop() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.detector.isTargetRunning = true
        fixture.controller.configureAutomationTarget(bundleIdentifier: "com.example.Renderer", name: "Renderer")
        fixture.controller.setAppAutomationEnabled(true)

        fixture.detector.isTargetRunning = false
        fixture.controller.reconcileAppAutomation(now: Date(timeIntervalSince1970: 20_000))
        XCTAssertNotNil(fixture.controller.state.appAutomationExitDeadline)

        fixture.detector.isTargetRunning = true
        fixture.controller.reconcileAppAutomation(now: Date(timeIntervalSince1970: 20_100))

        XCTAssertNil(fixture.controller.state.appAutomationExitDeadline)
        XCTAssertTrue(fixture.controller.state.isAwakeEnabled)
    }

    func testManualStopSuppressesAutomationUntilTargetRelaunches() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.detector.isTargetRunning = true
        fixture.controller.configureAutomationTarget(bundleIdentifier: "com.example.Renderer", name: "Renderer")
        fixture.controller.setAppAutomationEnabled(true)
        fixture.controller.stopAll()
        fixture.controller.reconcileAppAutomation()
        XCTAssertFalse(fixture.controller.state.isAwakeEnabled)

        fixture.detector.isTargetRunning = false
        fixture.controller.reconcileAppAutomation()
        fixture.detector.isTargetRunning = true
        fixture.controller.reconcileAppAutomation()

        XCTAssertTrue(fixture.controller.state.isAwakeEnabled)
        XCTAssertEqual(fixture.controller.state.sessionSource, .appAutomation)
    }

    func testQuickAwayReplacesSessionAndRestoresBrightnessWhenReturning() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.controller.startWake(duration: .twoHours)
        fixture.controller.setQuickAwayDuration(minutes: 30)
        fixture.controller.setQuickAwayBrightness(step: 1)
        fixture.controller.startQuickAway()

        XCTAssertEqual(fixture.controller.state.sessionSource, .quickAway)
        XCTAssertEqual(fixture.brightness.lastAppliedStep, 7)
        XCTAssertEqual(fixture.brightness.applyCount, 1)

        fixture.controller.endQuickAway()

        XCTAssertFalse(fixture.controller.state.isAwakeEnabled)
        XCTAssertEqual(fixture.brightness.restoreCount, 1)
    }

    func testQuickAwaySettingsAreClamped() {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }

        fixture.controller.setQuickAwayDuration(minutes: 1_000)
        fixture.controller.setQuickAwayBrightness(step: 0)
        fixture.controller.setQuickAwayCopyStyle(.cyberCare)

        XCTAssertEqual(fixture.controller.state.quickAway.durationMinutes, 240)
        XCTAssertEqual(fixture.controller.state.quickAway.brightnessStep, 7)
        XCTAssertEqual(fixture.controller.state.quickAway.brightnessPercent, 10)
        XCTAssertEqual(fixture.controller.state.quickAway.copyStyle, .cyberCare)
    }

    private func makeFixture() -> AutomationFixture {
        let suite = "AwakeMacTests.\(UUID().uuidString)"
        let detector = TestApplicationDetector()
        let brightness = TestBrightnessService()
        let controller = WakeController(
            store: AwakeMac.SharedStateStore(suiteName: suite),
            loginItemService: AutomationTestLoginItemService(),
            runningAppDetector: detector,
            brightnessService: brightness,
            preferences: UserDefaults(suiteName: suite)!
        )
        return AutomationFixture(
            suite: suite,
            controller: controller,
            detector: detector,
            brightness: brightness
        )
    }
}

@MainActor
private struct AutomationFixture {
    let suite: String
    let controller: WakeController
    let detector: TestApplicationDetector
    let brightness: TestBrightnessService

    func cleanUp() {
        controller.stopAll()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class TestApplicationDetector: ApplicationRunningDetecting {
    var isTargetRunning = false

    func isRunning(bundleIdentifier: String) -> Bool {
        isTargetRunning
    }
}

@MainActor
private final class TestBrightnessService: DisplayBrightnessServicing {
    var applyCount = 0
    var restoreCount = 0
    var lastAppliedStep: Int?

    func canAdjustAnyDisplay() -> Bool { true }

    func applyTemporaryBrightness(step: Int) -> BrightnessAdjustmentResult {
        applyCount += 1
        lastAppliedStep = step
        return BrightnessAdjustmentResult(adjustedDisplayCount: 1, unsupportedDisplayCount: 0)
    }

    func restoreTemporaryBrightness() -> BrightnessRestoreResult {
        restoreCount += 1
        return BrightnessRestoreResult(restoredDisplayCount: 1, failedDisplayCount: 0)
    }
}

@MainActor
private final class AutomationTestLoginItemService: LoginItemServicing {
    var status = SMAppService.Status.enabled

    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}
