import AppIntents
import Foundation
import WidgetKit

struct ToggleWakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle AwakeMac"
    static let description = IntentDescription("Starts or stops the normal wake session.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        let store = SharedStateStore()
        var state = store.loadState()
        if state.isAwakeEnabled {
            state.stop()
            store.writePendingAction(PendingWakeAction(kind: .stop))
        } else {
            state.start(duration: state.selectedDuration)
            state.isLidModeEnabled = false
            store.writePendingAction(PendingWakeAction(kind: .start))
        }
        store.saveState(state)
        notifyHostAndWidgets()
        return .result()
    }
}

struct StartWakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start AwakeMac"
    static let description = IntentDescription("Starts a normal wake session for a preset duration.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Minutes")
    var minutes: Int

    init() {
        minutes = 60
    }

    init(minutes: Int) {
        self.minutes = minutes
    }

    func perform() async throws -> some IntentResult {
        let duration = WakeDuration(minutes: minutes == 0 ? nil : min(1_440, max(1, minutes)))
        let store = SharedStateStore()
        var state = store.loadState()
        state.start(duration: duration)
        state.isLidModeEnabled = false
        store.saveState(state)
        store.writePendingAction(
            PendingWakeAction(kind: .start, minutes: duration.minutes, hasExplicitDuration: true)
        )
        notifyHostAndWidgets()
        return .result()
    }
}

struct StopWakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop AwakeMac"
    static let description = IntentDescription("Stops the wake session and restores normal sleep behavior.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        let store = SharedStateStore()
        var state = store.loadState()
        state.stop()
        store.saveState(state)
        store.writePendingAction(PendingWakeAction(kind: .stop))
        notifyHostAndWidgets()
        return .result()
    }
}

private func notifyHostAndWidgets() {
    DistributedNotificationCenter.default().post(
        name: SharedStateStore.distributedNotification,
        object: nil
    )
    WidgetCenter.shared.reloadAllTimelines()
}
