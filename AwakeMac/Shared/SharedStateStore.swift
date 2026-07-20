import Foundation

final class SharedStateStore: @unchecked Sendable {
    static let appGroupIdentifier = "group.com.zhuhai.AwakeMac"
    static let distributedNotification = Notification.Name("com.zhuhai.AwakeMac.pendingAction")

    private enum Key {
        static let wakeState = "wakeState.v1"
        static let pendingAction = "pendingAction.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(suiteName: String? = SharedStateStore.appGroupIdentifier) {
        if let suiteName, let shared = UserDefaults(suiteName: suiteName) {
            defaults = shared
        } else {
            defaults = .standard
        }
    }

    func loadState() -> WakeState {
        guard
            let data = defaults.data(forKey: Key.wakeState),
            let state = try? decoder.decode(WakeState.self, from: data)
        else { return WakeState() }
        return state
    }

    func saveState(_ state: WakeState) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: Key.wakeState)
    }

    func writePendingAction(_ action: PendingWakeAction) {
        guard let data = try? encoder.encode(action) else { return }
        defaults.set(data, forKey: Key.pendingAction)
    }

    func consumePendingAction() -> PendingWakeAction? {
        guard
            let data = defaults.data(forKey: Key.pendingAction),
            let action = try? decoder.decode(PendingWakeAction.self, from: data)
        else { return nil }
        defaults.removeObject(forKey: Key.pendingAction)
        return action
    }
}

