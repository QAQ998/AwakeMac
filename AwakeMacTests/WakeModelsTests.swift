import XCTest

final class WakeModelsTests: XCTestCase {
    func testFiniteDurationCreatesDeadline() {
        let start = Date(timeIntervalSince1970: 1_000)
        let deadline = WakeDuration(minutes: 30).deadline(from: start)
        XCTAssertEqual(deadline, Date(timeIntervalSince1970: 2_800))
    }

    func testUnlimitedDurationHasNoDeadline() {
        XCTAssertNil(WakeDuration.unlimited.deadline())
    }

    func testStoppingWakeStateAlsoDisablesLidMode() {
        var state = WakeState()
        state.start(duration: .oneHour)
        state.isLidModeEnabled = true
        state.stop()
        XCTAssertFalse(state.isAwakeEnabled)
        XCTAssertFalse(state.isLidModeEnabled)
        XCTAssertNil(state.endAt)
    }

    func testChangingDurationRestartsFromProvidedDate() {
        var state = WakeState()
        let start = Date(timeIntervalSince1970: 10_000)
        state.start(duration: .twoHours, now: start)
        XCTAssertEqual(state.endAt, start.addingTimeInterval(7_200))
        XCTAssertEqual(state.selectedDuration, .twoHours)
    }

    func testLegacyStateDecodesWithNewAutomationDefaults() throws {
        let data = Data(
            #"{"isAwakeEnabled":false,"isLidModeEnabled":false,"selectedDuration":{"minutes":60},"language":"english","safetyStatus":"normal"}"#.utf8
        )

        let state = try JSONDecoder().decode(WakeState.self, from: data)

        XCTAssertEqual(state.sessionSource, .manual)
        XCTAssertEqual(state.appAutomation, AppAutomationSettings())
        XCTAssertEqual(state.quickAway, QuickAwaySettings())
    }
}
