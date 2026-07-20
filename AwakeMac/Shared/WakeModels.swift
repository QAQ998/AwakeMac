import Foundation

enum WakeSessionSource: String, Codable, Sendable {
    case manual
    case appAutomation
    case quickAway
}

enum AppExitGracePreset: Int, Codable, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case thirtyMinutes = 30

    var id: Int { rawValue }
    var interval: TimeInterval { TimeInterval(rawValue * 60) }
}

enum QuickAwayCopyStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case briefAway
    case aquaticResearch
    case cyberCare

    var id: String { rawValue }

    var localizationKeySegment: String {
        switch self {
        case .briefAway: "brief"
        case .aquaticResearch: "aquatic"
        case .cyberCare: "cyber"
        }
    }
}

struct AppAutomationSettings: Codable, Equatable, Sendable {
    var isEnabled = false
    var targetBundleIdentifier: String?
    var targetAppName: String?
    var exitGrace = AppExitGracePreset.tenMinutes

    var hasTarget: Bool {
        guard let targetBundleIdentifier else { return false }
        return !targetBundleIdentifier.isEmpty
    }
}

struct QuickAwaySettings: Codable, Equatable, Sendable {
    var durationMinutes = 30
    var brightnessStep = 1
    var copyStyle = QuickAwayCopyStyle.briefAway

    /// The display API keeps all 64 native steps. UI surfaces show an integer
    /// percentage while preserving every selectable underlying step.
    var brightnessPercent: Int {
        if brightnessStep == 1 { return 1 }
        return Int((Double(brightnessStep) / 64.0 * 100.0).rounded())
    }

    mutating func clamp() {
        durationMinutes = min(240, max(5, durationMinutes))
        brightnessStep = min(64, max(1, brightnessStep))
    }
}

struct WakeDuration: Codable, Hashable, Identifiable, Sendable {
    /// Nil means unlimited. Finite values are clamped by the UI to 1 minute...24 hours.
    let minutes: Int?

    var id: String { minutes.map(String.init) ?? "unlimited" }
    var isUnlimited: Bool { minutes == nil }

    func deadline(from start: Date = .now) -> Date? {
        minutes.map { start.addingTimeInterval(TimeInterval($0 * 60)) }
    }

    static let fifteenMinutes = WakeDuration(minutes: 15)
    static let thirtyMinutes = WakeDuration(minutes: 30)
    static let oneHour = WakeDuration(minutes: 60)
    static let twoHours = WakeDuration(minutes: 120)
    static let fourHours = WakeDuration(minutes: 240)
    static let unlimited = WakeDuration(minutes: nil)

    static let presets: [WakeDuration] = [
        .fifteenMinutes, .thirtyMinutes, .oneHour, .twoHours, .fourHours, .unlimited
    ]
}

enum PowerSafetyStatus: String, Codable, Sendable {
    case normal
    case helperApprovalRequired
    case helperUnavailable
    case lowBattery
    case thermalPressure
    case unsupportedHardware
}

struct WakeState: Codable, Equatable, Sendable {
    var isAwakeEnabled = false
    var endAt: Date?
    var isLidModeEnabled = false
    var selectedDuration = WakeDuration.oneHour
    var language = AppLanguage.systemDefault
    var safetyStatus = PowerSafetyStatus.normal
    var hardwareHasClamshell: Bool?
    var sessionSource = WakeSessionSource.manual
    var appAutomation = AppAutomationSettings()
    var appAutomationExitDeadline: Date?
    var quickAway = QuickAwaySettings()

    var isExpired: Bool {
        guard let endAt else { return false }
        return endAt <= .now
    }

    mutating func start(
        duration: WakeDuration,
        source: WakeSessionSource = .manual,
        updateSelectedDuration: Bool = true,
        now: Date = .now
    ) {
        if updateSelectedDuration {
            selectedDuration = duration
        }
        isAwakeEnabled = true
        endAt = duration.deadline(from: now)
        sessionSource = source
        if source != .appAutomation {
            appAutomationExitDeadline = nil
        }
    }

    mutating func stop() {
        isAwakeEnabled = false
        endAt = nil
        isLidModeEnabled = false
        safetyStatus = .normal
        sessionSource = .manual
        appAutomationExitDeadline = nil
    }


    private enum CodingKeys: String, CodingKey {
        case isAwakeEnabled
        case endAt
        case isLidModeEnabled
        case selectedDuration
        case language
        case safetyStatus
        case hardwareHasClamshell
        case sessionSource
        case appAutomation
        case appAutomationExitDeadline
        case quickAway
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAwakeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAwakeEnabled) ?? false
        endAt = try container.decodeIfPresent(Date.self, forKey: .endAt)
        isLidModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLidModeEnabled) ?? false
        selectedDuration = try container.decodeIfPresent(WakeDuration.self, forKey: .selectedDuration) ?? .oneHour
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .systemDefault
        safetyStatus = try container.decodeIfPresent(PowerSafetyStatus.self, forKey: .safetyStatus) ?? .normal
        hardwareHasClamshell = try container.decodeIfPresent(Bool.self, forKey: .hardwareHasClamshell)
        sessionSource = try container.decodeIfPresent(WakeSessionSource.self, forKey: .sessionSource) ?? .manual
        appAutomation = try container.decodeIfPresent(AppAutomationSettings.self, forKey: .appAutomation) ?? .init()
        appAutomationExitDeadline = try container.decodeIfPresent(Date.self, forKey: .appAutomationExitDeadline)
        quickAway = try container.decodeIfPresent(QuickAwaySettings.self, forKey: .quickAway) ?? .init()
        quickAway.clamp()
    }
}

enum PendingWakeActionKind: String, Codable, Sendable {
    case toggle
    case start
    case stop
}

struct PendingWakeAction: Codable, Sendable {
    let id: UUID
    let kind: PendingWakeActionKind
    let minutes: Int?
    let hasExplicitDuration: Bool

    init(kind: PendingWakeActionKind, minutes: Int? = nil, hasExplicitDuration: Bool = false) {
        self.id = UUID()
        self.kind = kind
        self.minutes = minutes
        self.hasExplicitDuration = hasExplicitDuration
    }

    var duration: WakeDuration? {
        hasExplicitDuration ? WakeDuration(minutes: minutes) : nil
    }
}
