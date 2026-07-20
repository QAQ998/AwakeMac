import AppKit
import Foundation
import ServiceManagement
import WidgetKit

@MainActor
final class WakeController: NSObject, ObservableObject {
    @Published private(set) var state: WakeState
    @Published private(set) var capabilities: HardwareCapabilities
    @Published private(set) var now = Date.now
    @Published private(set) var loginItemEnabled = false
    @Published private(set) var helperServiceStatus = LocalPowerHelperStatus.notInstalled
    @Published private(set) var isLidModeRequestInFlight = false
    @Published private(set) var canAdjustDisplayBrightness = false
    @Published private(set) var lastBrightnessAdjustment = BrightnessAdjustmentResult(
        adjustedDisplayCount: 0,
        unsupportedDisplayCount: 0
    )
    @Published var lastError: String?

    private let store: SharedStateStore
    private let helperClient: any PowerHelperServicing
    private let helperInstaller: any LocalPowerHelperInstalling
    private let loginItemService: any LoginItemServicing
    private let runningAppDetector: any ApplicationRunningDetecting
    private let brightnessService: any DisplayBrightnessServicing
    private let preferences: UserDefaults
    private var activityToken: NSObjectProtocol?
    private var tickTimer: Timer?
    private var safetyTimer: Timer?
    private var leaseTimer: Timer?
    private var automationPollTimer: Timer?
    private var leaseID: String?
    private var lastTargetRunningState: Bool?
    private var automationSuppressedUntilTargetExits = false
    private let notificationObservations = NotificationObservationBag()
    private var hasStarted = false
    private static let loginItemConfiguredKey = "didConfigureLoginItem"

    init(
        store: SharedStateStore = SharedStateStore(),
        helperClient: any PowerHelperServicing = PowerHelperClient(),
        helperInstaller: any LocalPowerHelperInstalling = LocalPowerHelperInstaller(),
        loginItemService: any LoginItemServicing = SMAppService.mainApp,
        runningAppDetector: any ApplicationRunningDetecting = WorkspaceApplicationRunningDetector(),
        brightnessService: (any DisplayBrightnessServicing)? = nil,
        preferences: UserDefaults = .standard,
        detector: HardwareCapabilityDetector = HardwareCapabilityDetector()
    ) {
        self.store = store
        self.helperClient = helperClient
        self.helperInstaller = helperInstaller
        self.loginItemService = loginItemService
        self.runningAppDetector = runningAppDetector
        self.brightnessService = brightnessService ?? DisplayBrightnessController(preferences: preferences)
        self.preferences = preferences
        self.state = store.loadState()
        self.capabilities = detector.detect()
        super.init()
        self.state.language = .systemDefault
        self.state.hardwareHasClamshell = self.capabilities.hasClamshell
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let recoveryResult = brightnessService.restoreTemporaryBrightness()
        if recoveryResult.failedDisplayCount > 0 {
            lastError = L10n.text("quickAway.restoreFailed", language: state.language)
        }
        if state.sessionSource == .quickAway {
            state.stop()
        }
        // App Link is intentionally hidden in this release. Clear a previously
        // enabled setting so no automation remains active without visible controls.
        if state.appAutomation.isEnabled {
            state.appAutomation.isEnabled = false
            state.appAutomationExitDeadline = nil
            if state.sessionSource == .appAutomation {
                state.stop()
            }
        }
        state.isLidModeEnabled = false
        if state.isExpired { state.stop() }
        if state.isAwakeEnabled { beginWakeActivity() }
        store.saveState(state)

        refreshServiceStatuses()
        if helperServiceStatus == .installed, state.safetyStatus == .helperApprovalRequired {
            state.safetyStatus = .normal
            store.saveState(state)
        }
        enableLoginItemByDefault()
        consumePendingAction()
        canAdjustDisplayBrightness = brightnessService.canAdjustAnyDisplay()

        let pendingActionObserver = DistributedNotificationCenter.default().addObserver(
            forName: SharedStateStore.distributedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.consumePendingAction()
            }
        }
        notificationObservations.insert(
            pendingActionObserver,
            center: DistributedNotificationCenter.default()
        )

        let thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateSafety()
            }
        }
        notificationObservations.insert(
            thermalStateObserver,
            center: NotificationCenter.default
        )

        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ] {
            let token = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reconcileAppAutomation()
                }
            }
            notificationObservations.insert(token, center: NSWorkspace.shared.notificationCenter)
        }

        let displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.canAdjustDisplayBrightness = self.brightnessService.canAdjustAnyDisplay()
            }
        }
        notificationObservations.insert(displayObserver, center: NotificationCenter.default)

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateSafety() }
        }
        automationPollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcileAppAutomation() }
        }
        reconcileAppAutomation()
    }

    func toggleWake() {
        state.isAwakeEnabled ? stopAll() : startWake(duration: state.selectedDuration)
    }

    func startWake(duration: WakeDuration) {
        prepareForManualSession()
        state.start(duration: duration, source: .manual)
        beginWakeActivity()
        persistAndRefresh()
    }

    func setDuration(_ duration: WakeDuration) {
        if state.isAwakeEnabled, state.sessionSource != .manual {
            prepareForManualSession()
            state.sessionSource = .manual
        }
        state.selectedDuration = duration
        if state.isAwakeEnabled {
            state.endAt = duration.deadline()
        }
        persistAndRefresh()
    }

    func setCustomDuration(minutes: Int) {
        setDuration(WakeDuration(minutes: min(1_440, max(1, minutes))))
    }

    func stopAll() {
        stopAll(suppressAutomationForCurrentRun: true)
    }

    private func stopAll(suppressAutomationForCurrentRun: Bool) {
        if suppressAutomationForCurrentRun, isTargetApplicationRunning {
            automationSuppressedUntilTargetExits = true
        }
        if state.sessionSource == .quickAway {
            let restoreResult = brightnessService.restoreTemporaryBrightness()
            if restoreResult.failedDisplayCount > 0 {
                lastError = L10n.text("quickAway.restoreFailed", language: state.language)
            }
        }
        endWakeActivity()
        let wasLidActive = state.isLidModeEnabled
        state.stop()
        leaseID = nil
        leaseTimer?.invalidate()
        leaseTimer = nil
        persistAndRefresh()
        if wasLidActive {
            Task { try? await helperClient.disable() }
        }
    }

    func stopAndQuit() {
        stopAll()
        NSApplication.shared.terminate(nil)
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        lastError = nil
        preferences.set(true, forKey: Self.loginItemConfiguredKey)

        do {
            if enabled {
                switch loginItemService.status {
                case .notRegistered, .notFound:
                    try loginItemService.register()
                case .requiresApproval:
                    lastError = L10n.text("login.approvalRequired", language: state.language)
                    loginItemService.openSystemSettings()
                case .enabled:
                    break
                @unknown default:
                    try loginItemService.register()
                }
            } else {
                switch loginItemService.status {
                case .enabled, .requiresApproval:
                    try loginItemService.unregister()
                case .notRegistered, .notFound:
                    break
                @unknown default:
                    try loginItemService.unregister()
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
        refreshServiceStatuses()
    }

    func selectAutomationApplication(at url: URL) {
        lastError = nil
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            lastError = L10n.text("automation.invalidApp", language: state.language)
            return
        }
        let appName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        configureAutomationTarget(bundleIdentifier: bundleIdentifier, name: appName)
    }

    func configureAutomationTarget(bundleIdentifier: String, name: String) {
        if state.sessionSource == .appAutomation {
            stopAll(suppressAutomationForCurrentRun: false)
        }
        state.appAutomation.targetBundleIdentifier = bundleIdentifier
        state.appAutomation.targetAppName = name
        state.appAutomationExitDeadline = nil
        lastTargetRunningState = nil
        automationSuppressedUntilTargetExits = false
        persistAndRefresh()
        reconcileAppAutomation()
    }

    func setAppAutomationEnabled(_ enabled: Bool) {
        lastError = nil
        guard !enabled || state.appAutomation.hasTarget else {
            lastError = L10n.text("automation.chooseFirst", language: state.language)
            return
        }
        state.appAutomation.isEnabled = enabled
        state.appAutomationExitDeadline = nil
        lastTargetRunningState = nil
        automationSuppressedUntilTargetExits = false
        if !enabled, state.sessionSource == .appAutomation {
            stopAll(suppressAutomationForCurrentRun: false)
        } else {
            persistAndRefresh()
            reconcileAppAutomation()
        }
    }

    func setAppExitGrace(_ grace: AppExitGracePreset) {
        state.appAutomation.exitGrace = grace
        if state.sessionSource == .appAutomation,
           !isTargetApplicationRunning,
           state.appAutomationExitDeadline != nil {
            state.appAutomationExitDeadline = Date.now.addingTimeInterval(grace.interval)
        }
        persistAndRefresh()
        evaluateAutomationDeadline()
    }

    func setQuickAwayCopyStyle(_ style: QuickAwayCopyStyle) {
        state.quickAway.copyStyle = style
        persistAndRefresh()
    }

    func setQuickAwayDuration(minutes: Int) {
        state.quickAway.durationMinutes = min(240, max(5, minutes))
        persistAndRefresh()
    }

    func setQuickAwayBrightness(step: Int) {
        state.quickAway.brightnessStep = min(64, max(1, step))
        persistAndRefresh()
    }

    func startQuickAway() {
        if isTargetApplicationRunning {
            automationSuppressedUntilTargetExits = true
        }

        let wasLidActive = state.isLidModeEnabled
        state.isLidModeEnabled = false
        leaseID = nil
        leaseTimer?.invalidate()
        leaseTimer = nil
        if wasLidActive {
            Task { try? await helperClient.disable() }
        }

        state.start(
            duration: WakeDuration(minutes: state.quickAway.durationMinutes),
            source: .quickAway,
            updateSelectedDuration: false
        )
        beginWakeActivity()
        lastBrightnessAdjustment = brightnessService.applyTemporaryBrightness(
            step: state.quickAway.brightnessStep
        )
        canAdjustDisplayBrightness = brightnessService.canAdjustAnyDisplay()
        persistAndRefresh()
    }

    func endQuickAway() {
        guard state.sessionSource == .quickAway else { return }
        stopAll(suppressAutomationForCurrentRun: true)
    }

    var isTargetApplicationRunning: Bool {
        guard state.appAutomation.isEnabled,
              let bundleIdentifier = state.appAutomation.targetBundleIdentifier else { return false }
        return runningAppDetector.isRunning(bundleIdentifier: bundleIdentifier)
    }

    var appAutomationStatusText: String? {
        guard state.appAutomation.isEnabled,
              let name = state.appAutomation.targetAppName else { return nil }
        if state.sessionSource == .appAutomation,
           let deadline = state.appAutomationExitDeadline {
            let seconds = max(0, Int(deadline.timeIntervalSince(now)))
            return String(
                format: L10n.text("automation.exitCountdown", language: state.language),
                name,
                seconds / 60,
                seconds % 60
            )
        }
        if state.sessionSource == .appAutomation {
            return String(
                format: L10n.text("automation.active", language: state.language),
                name
            )
        }
        return nil
    }

    func requestLidMode() async -> Bool {
        if state.isLidModeEnabled { return true }
        guard !isLidModeRequestInFlight else { return false }
        isLidModeRequestInFlight = true
        defer { isLidModeRequestInFlight = false }

        guard capabilities.hasClamshell, state.isAwakeEnabled else {
            state.safetyStatus = .unsupportedHardware
            persistAndRefresh()
            return false
        }

        guard await installLocalHelperIfNeeded() else {
            state.safetyStatus = .helperUnavailable
            persistAndRefresh()
            return false
        }

        let newLeaseID = UUID().uuidString
        do {
            try await helperClient.enable(leaseID: newLeaseID, deadline: state.endAt)
            leaseID = newLeaseID
            state.isLidModeEnabled = true
            state.safetyStatus = .normal
            startLeaseTimer()
            NotificationService.requestAuthorization()
            persistAndRefresh()
            return true
        } catch {
            state.safetyStatus = .helperUnavailable
            lastError = error.localizedDescription
            persistAndRefresh()
            return false
        }
    }

    func disableLidMode() {
        state.isLidModeEnabled = false
        leaseID = nil
        leaseTimer?.invalidate()
        leaseTimer = nil
        persistAndRefresh()
        Task {
            do { try await helperClient.disable() }
            catch { lastError = error.localizedDescription }
        }
    }

    func installLocalHelper() async -> Bool {
        helperServiceStatus = .installing
        do {
            try await helperInstaller.install()
            refreshServiceStatuses()
            guard helperServiceStatus == .installed else {
                helperServiceStatus = .unavailable
                lastError = L10n.text("helper.installFailed", language: state.language)
                return false
            }
            try? await Task.sleep(for: .milliseconds(400))
            state.safetyStatus = .normal
            persistAndRefresh()
            return true
        } catch {
            helperServiceStatus = helperInstaller.status()
            state.safetyStatus = .helperUnavailable
            lastError = error.localizedDescription
            persistAndRefresh()
            return false
        }
    }

    func uninstallLocalHelper() async {
        state.isLidModeEnabled = false
        leaseID = nil
        leaseTimer?.invalidate()
        leaseTimer = nil
        persistAndRefresh()

        do {
            try await helperInstaller.uninstall()
            refreshServiceStatuses()
            state.safetyStatus = .normal
        } catch {
            helperServiceStatus = .unavailable
            lastError = error.localizedDescription
        }
        persistAndRefresh()
    }

    func durationLabel(_ duration: WakeDuration? = nil) -> String {
        let duration = duration ?? state.selectedDuration
        guard let minutes = duration.minutes else { return L10n.text("duration.unlimited", language: state.language) }
        if minutes < 60 {
            return String(format: L10n.text("duration.minutes", language: state.language), minutes)
        }
        let hours = Double(minutes) / 60
        if hours.rounded() == hours {
            return String(format: L10n.text("duration.hours", language: state.language), Int(hours))
        }
        return String(format: L10n.text("duration.minutes", language: state.language), minutes)
    }

    var remainingText: String {
        guard state.isAwakeEnabled else { return L10n.text("status.off", language: state.language) }
        if let appAutomationStatusText {
            return appAutomationStatusText
        }
        if state.sessionSource == .quickAway {
            let prefixKey = state.quickAway.copyStyle == .aquaticResearch
                ? "quickAway.aquatic.active"
                : "quickAway.cyber.active"
            let status = L10n.text(prefixKey, language: state.language)
            guard let endAt = state.endAt else { return status }
            let minutes = max(1, Int(ceil(endAt.timeIntervalSince(now) / 60)))
            return String(
                format: L10n.text("quickAway.activeRemaining", language: state.language),
                status,
                minutes
            )
        }
        guard let endAt = state.endAt else { return L10n.text("duration.unlimited", language: state.language) }
        let seconds = max(0, Int(endAt.timeIntervalSince(now)))
        if seconds < 60 { return String(format: L10n.text("remaining.seconds", language: state.language), seconds) }
        if seconds < 3_600 { return String(format: L10n.text("remaining.minutes", language: state.language), Int(ceil(Double(seconds) / 60))) }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return String(format: L10n.text("remaining.hoursMinutes", language: state.language), hours, minutes)
    }

    var isUrgent: Bool {
        guard let endAt = state.endAt else { return false }
        return state.isAwakeEnabled && endAt.timeIntervalSince(now) <= 300
    }

    private func consumePendingAction() {
        guard let action = store.consumePendingAction() else { return }
        switch action.kind {
        case .toggle:
            toggleWake()
        case .start:
            startWake(duration: action.duration ?? state.selectedDuration)
        case .stop:
            stopAll()
        }
    }

    private func tick() {
        now = .now
        evaluateAutomationDeadline()
        if state.isAwakeEnabled, let endAt = state.endAt, endAt <= now {
            if state.sessionSource == .quickAway {
                if isTargetApplicationRunning {
                    automationSuppressedUntilTargetExits = true
                }
                let style = state.quickAway.copyStyle
                stopAll(suppressAutomationForCurrentRun: false)
                NotificationService.post(
                    title: L10n.text(
                        style == .aquaticResearch
                            ? "quickAway.aquatic.notificationTitle"
                            : "quickAway.cyber.notificationTitle",
                        language: state.language
                    ),
                    body: L10n.text(
                        style == .aquaticResearch
                            ? "quickAway.aquatic.notificationBody"
                            : "quickAway.cyber.notificationBody",
                        language: state.language
                    )
                )
            } else {
                stopAll(suppressAutomationForCurrentRun: false)
                reconcileAppAutomation()
                NotificationService.post(
                    title: L10n.text("notification.timer.title", language: state.language),
                    body: L10n.text("notification.timer.body", language: state.language)
                )
            }
        }
    }

    private func prepareForManualSession() {
        if isTargetApplicationRunning {
            automationSuppressedUntilTargetExits = true
        }
        if state.sessionSource == .quickAway {
            _ = brightnessService.restoreTemporaryBrightness()
        }
        state.appAutomationExitDeadline = nil
    }

    func reconcileAppAutomation(now: Date = .now) {
        guard state.appAutomation.isEnabled,
              let bundleIdentifier = state.appAutomation.targetBundleIdentifier else {
            lastTargetRunningState = nil
            return
        }

        let isRunning = runningAppDetector.isRunning(bundleIdentifier: bundleIdentifier)
        defer { lastTargetRunningState = isRunning }

        if isRunning {
            var stateChanged = state.appAutomationExitDeadline != nil
            state.appAutomationExitDeadline = nil
            if !automationSuppressedUntilTargetExits, !state.isAwakeEnabled {
                state.start(
                    duration: .unlimited,
                    source: .appAutomation,
                    updateSelectedDuration: false,
                    now: now
                )
                beginWakeActivity()
                stateChanged = true
            }
            if stateChanged {
                persistAndRefresh()
            }
            return
        }

        if lastTargetRunningState == true {
            automationSuppressedUntilTargetExits = false
        }

        guard state.sessionSource == .appAutomation, state.isAwakeEnabled else {
            if state.appAutomationExitDeadline != nil {
                state.appAutomationExitDeadline = nil
                persistAndRefresh()
            }
            return
        }

        if state.appAutomationExitDeadline == nil {
            state.appAutomationExitDeadline = now.addingTimeInterval(state.appAutomation.exitGrace.interval)
            persistAndRefresh()
        }
        evaluateAutomationDeadline(now: now)
    }

    private func evaluateAutomationDeadline(now: Date = .now) {
        guard state.sessionSource == .appAutomation,
              let deadline = state.appAutomationExitDeadline,
              deadline <= now else { return }
        stopAll(suppressAutomationForCurrentRun: false)
        NotificationService.post(
            title: L10n.text("automation.notificationTitle", language: state.language),
            body: L10n.text("automation.notificationBody", language: state.language)
        )
    }

    private func evaluateSafety() {
        guard state.isLidModeEnabled else { return }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical {
            disableLidForSafety(status: .thermalPressure, bodyKey: "notification.thermal.body")
            return
        }
        let power = PowerMonitor.snapshot()
        if power.isOnBattery, let percent = power.batteryPercent, percent <= 20 {
            disableLidForSafety(status: .lowBattery, bodyKey: "notification.battery.body")
        }
    }

    private func disableLidForSafety(status: PowerSafetyStatus, bodyKey: String) {
        disableLidMode()
        state.safetyStatus = status
        persistAndRefresh()
        NotificationService.post(
            title: L10n.text("notification.safety.title", language: state.language),
            body: L10n.text(bodyKey, language: state.language)
        )
    }

    private func beginWakeActivity() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
            reason: "AwakeMac user-requested wake session"
        )
    }

    private func endWakeActivity() {
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }

    private func startLeaseTimer() {
        leaseTimer?.invalidate()
        leaseTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let leaseID = self.leaseID else { return }
                if !(await self.helperClient.renew(leaseID: leaseID)) {
                    self.state.isLidModeEnabled = false
                    self.state.safetyStatus = .helperUnavailable
                    self.leaseID = nil
                    self.leaseTimer?.invalidate()
                    self.persistAndRefresh()
                }
            }
        }
    }

    private func installLocalHelperIfNeeded() async -> Bool {
        refreshServiceStatuses()
        guard helperServiceStatus != .installed else { return true }
        return await installLocalHelper()
    }

    private func persistAndRefresh() {
        store.saveState(state)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshServiceStatuses() {
        loginItemEnabled = loginItemService.status == .enabled
        helperServiceStatus = helperInstaller.status()
    }

    private func enableLoginItemByDefault() {
        guard !preferences.bool(forKey: Self.loginItemConfiguredKey) else { return }

        do {
            switch loginItemService.status {
            case .notRegistered, .notFound:
                try loginItemService.register()
            case .enabled, .requiresApproval:
                break
            @unknown default:
                try loginItemService.register()
            }
            preferences.set(true, forKey: Self.loginItemConfiguredKey)
        } catch {
            lastError = error.localizedDescription
        }
        refreshServiceStatuses()
    }
}

private final class NotificationObservationBag: @unchecked Sendable {
    private var observations: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func insert(_ token: NSObjectProtocol, center: NotificationCenter) {
        observations.append((center, token))
    }

    deinit {
        observations.forEach { observation in
            observation.center.removeObserver(observation.token)
        }
    }
}
