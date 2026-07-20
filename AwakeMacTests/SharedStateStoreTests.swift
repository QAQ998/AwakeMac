import XCTest

final class SharedStateStoreTests: XCTestCase {
    func testStateRoundTripAndPendingActionConsumption() {
        let suite = "AwakeMacTests.\(UUID().uuidString)"
        let store = SharedStateStore(suiteName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        var state = WakeState()
        state.language = .zhHans
        state.start(duration: .thirtyMinutes, now: Date(timeIntervalSince1970: 5_000))
        store.saveState(state)

        XCTAssertEqual(store.loadState(), state)

        store.writePendingAction(PendingWakeAction(kind: .stop))
        XCTAssertEqual(store.consumePendingAction()?.kind, .stop)
        XCTAssertNil(store.consumePendingAction())
    }
}

