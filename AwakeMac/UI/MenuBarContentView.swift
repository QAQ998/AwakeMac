import ServiceManagement
import SwiftUI

struct MenuBarContentView: View {
    enum Presentation {
        case mainWindow
        case menuBar
    }

    @EnvironmentObject private var controller: WakeController
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var customDurationEditor = CustomDurationEditorState()
    @State private var lidPrerequisiteFeedback = LidPrerequisiteFeedbackState()
    @State private var showsLidModeConfirmation = false
    @State private var showsQuickAwayConfirmation = false
    @State private var prerequisiteResetTask: Task<Void, Never>?

    let presentation: Presentation

    init(presentation: Presentation = .mainWindow) {
        self.presentation = presentation
    }

    private var language: AppLanguage { controller.state.language }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            Divider()
            durationRow
            if customDurationEditor.isPresented {
                Divider()
                inlineCustomDurationEditor
            }
            Divider()
            quickAwayRow
            if showsQuickAwayConfirmation {
                Divider()
                inlineQuickAwayConfirmation
            }
            Divider()
            lidRow
            if showsLidModeConfirmation {
                Divider()
                inlineLidModeConfirmation
            }
            safetyNotice
            Divider()
                .padding(.top, 12)
            footer
        }
        .padding(16)
        .frame(width: 340)
        .awakeTextOneStepLarger()
        .onAppear {
            if presentation == .menuBar {
                AppWindowCoordinator.menuBarControlDidAppear()
            }
        }
        .onDisappear {
            customDurationEditor.cancel()
            showsLidModeConfirmation = false
            showsQuickAwayConfirmation = false
            prerequisiteResetTask?.cancel()
            lidPrerequisiteFeedback.reset()
        }
        .alert(
            L10n.text("error.title", language: language),
            isPresented: Binding(
                get: {
                    controller.lastError != nil
                        && AppWindowCoordinator.shouldPresentSharedError(
                            on: presentation == .menuBar ? .menuBar : .mainControl
                        )
                },
                set: { if !$0 { controller.lastError = nil } }
            )
        ) {
            Button(L10n.text("common.ok", language: language)) { controller.lastError = nil }
        } message: {
            Text(controller.lastError ?? "")
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: controller.state.isAwakeEnabled ? "sun.max.fill" : "moon.zzz")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(controller.state.isAwakeEnabled ? Color.green : Color.secondary)
                .frame(width: 38, height: 38)
                .background(.quaternary, in: Circle())
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("wake.title", language: language))
                    .font(.headline)
                Text(controller.remainingText)
                    .font(.subheadline)
                    .foregroundStyle(controller.isUrgent ? Color.orange : Color.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                L10n.text("wake.title", language: language),
                isOn: Binding(
                    get: { controller.state.isAwakeEnabled },
                    set: { _ in
                        if controller.state.isAwakeEnabled {
                            showsLidModeConfirmation = false
                            showsQuickAwayConfirmation = false
                        }
                        controller.toggleWake()
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.large)
            .accessibilityHint(L10n.text("wake.toggle.hint", language: language))
        }
        .padding(.bottom, 14)
    }

    private var durationRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("duration.title", language: language))
                Text(L10n.text("duration.detail", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker(
                L10n.text("duration.title", language: language),
                selection: Binding(
                    get: { controller.state.selectedDuration },
                    set: { controller.setDuration($0) }
                )
            ) {
                ForEach(WakeDuration.presets) { duration in
                    Text(controller.durationLabel(duration)).tag(duration)
                }
                if !WakeDuration.presets.contains(controller.state.selectedDuration) {
                    Text(controller.durationLabel(controller.state.selectedDuration))
                        .tag(controller.state.selectedDuration)
                }
            }
            .labelsHidden()
            .frame(width: 112)

            Button {
                showsQuickAwayConfirmation = false
                showsLidModeConfirmation = false
                customDurationEditor.toggle(
                    currentMinutes: controller.state.selectedDuration.minutes ?? 90
                )
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.borderless)
            .help(L10n.text("duration.custom", language: language))
        }
        .padding(.vertical, 10)
    }

    private var lidRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "laptopcomputer")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("lid.title", language: language))
                Text(lidDetail)
                    .font(.caption)
                    .foregroundStyle(
                        lidPrerequisiteFeedback.isEmphasized
                            ? Color.red
                            : Color.secondary
                    )
                    .lineLimit(2)
                    .modifier(
                        ShakeEffect(
                            animatableData: CGFloat(lidPrerequisiteFeedback.shakeIteration)
                        )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(
                L10n.text("lid.title", language: language),
                isOn: Binding(
                    get: { controller.state.isLidModeEnabled },
                    set: { enabled in
                        if enabled {
                            requestLidModeConfirmation()
                        } else {
                            controller.disableLidMode()
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(
                !controller.capabilities.hasClamshell
                    || !controller.state.isAwakeEnabled
                    || controller.isLidModeRequestInFlight
            )
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay {
            if LidInteractionPolicy.activation(
                hasClamshell: controller.capabilities.hasClamshell,
                isAwake: controller.state.isAwakeEnabled
            ) == .showWakePrerequisite {
                Button(action: showWakePrerequisiteFeedback) {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("lid.title", language: language))
                .accessibilityHint(L10n.text("lid.enableWakeFirst", language: language))
            }
        }
    }

    private var quickAwayRow: some View {
        HStack(spacing: 10) {
            Image(systemName: controller.state.quickAway.copyStyle == .aquaticResearch ? "fish.fill" : "person.crop.circle.badge.clock")
                .foregroundStyle(controller.state.sessionSource == .quickAway ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(quickAwayRowTitle)
                Text(quickAwayRowDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if controller.state.sessionSource == .quickAway {
                Button(quickAwayReturnTitle) {
                    showsQuickAwayConfirmation = false
                    controller.endQuickAway()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(quickAwayStartButtonTitle) {
                    customDurationEditor.cancel()
                    showsLidModeConfirmation = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsQuickAwayConfirmation.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
    }

    private var inlineQuickAwayConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(quickAwayConfirmationTitle, systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text(quickAwayConfirmationBody)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if controller.state.isAwakeEnabled || controller.state.isLidModeEnabled {
                Text(L10n.text("quickAway.replacesSession", language: language))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !controller.canAdjustDisplayBrightness {
                Text(L10n.text("quickAway.noAdjustableDisplay", language: language))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(quickAwayCancelTitle, role: .cancel) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showsQuickAwayConfirmation = false
                    }
                }
                Button(quickAwayConfirmTitle) {
                    showsQuickAwayConfirmation = false
                    controller.startQuickAway()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var safetyNotice: some View {
        if let message = safetyMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    private var footer: some View {
        HStack {
            Button(L10n.text("settings.open", language: language)) {
                AppWindowCoordinator.openSettings(using: openSettings)
            }
                .buttonStyle(.link)
            Spacer()
            Button(L10n.text("quit.stop", language: language), role: .destructive) {
                controller.stopAndQuit()
            }
            .buttonStyle(.link)
        }
        .padding(.top, 11)
    }

    private var inlineCustomDurationEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("duration.custom.title", language: language))
                .font(.subheadline.weight(.semibold))
            Text(L10n.text("duration.custom.detail", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(
                    "",
                    value: $customDurationEditor.draftMinutes,
                    format: .number
                )
                .frame(width: 76)
                Text(L10n.text("unit.minutes", language: language))
                Spacer()
                Button(L10n.text("common.cancel", language: language), role: .cancel) {
                    customDurationEditor.cancel()
                }
                Button(L10n.text("common.apply", language: language)) {
                    guard let minutes = customDurationEditor.apply() else { return }
                    controller.setCustomDuration(minutes: minutes)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, 10)
    }

    private var inlineLidModeConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                L10n.text("lid.alert.title", language: language),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)

            Text(L10n.text("lid.alert.body", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(L10n.text("common.cancel", language: language), role: .cancel) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showsLidModeConfirmation = false
                    }
                }
                Button(lidAlertActionTitle) {
                    showsLidModeConfirmation = false
                    Task { _ = await controller.requestLidMode() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, 10)
    }

    private var lidDetail: String {
        guard controller.capabilities.hasClamshell else {
            return L10n.text("lid.unavailable", language: language)
        }
        guard controller.state.isAwakeEnabled else {
            return L10n.text("lid.enableWakeFirst", language: language)
        }
        if controller.state.isLidModeEnabled {
            return L10n.text("lid.active", language: language)
        }
        switch controller.helperServiceStatus {
        case .notInstalled:
            return L10n.text("lid.installRequired", language: language)
        case .updateRequired:
            return L10n.text("lid.updateRequired", language: language)
        case .installing:
            return L10n.text("lid.installing", language: language)
        case .unavailable:
            return L10n.text("safety.helperUnavailable", language: language)
        case .installed:
            return L10n.text("lid.experimental", language: language)
        }
    }

    private var lidAlertActionTitle: String {
        if controller.helperServiceStatus == .installed {
            return L10n.text("lid.alert.enable", language: language)
        }
        return L10n.text("lid.alert.continue", language: language)
    }

    private func requestLidModeConfirmation() {
        switch LidInteractionPolicy.activation(
            hasClamshell: controller.capabilities.hasClamshell,
            isAwake: controller.state.isAwakeEnabled
        ) {
        case .unavailable:
            return
        case .showWakePrerequisite:
            showWakePrerequisiteFeedback()
        case .requestConfirmation:
            if controller.helperServiceStatus == .installed {
                showsLidModeConfirmation = false
                Task { _ = await controller.requestLidMode() }
            } else if presentation == .menuBar {
                AppWindowCoordinator.continueMenuBarFlowInline {
                    toggleInlineLidModeConfirmation()
                }
            } else {
                toggleInlineLidModeConfirmation()
            }
        }
    }

    private func toggleInlineLidModeConfirmation() {
        customDurationEditor.cancel()
        showsQuickAwayConfirmation = false
        withAnimation(.easeInOut(duration: 0.2)) {
            showsLidModeConfirmation.toggle()
        }
    }

    private func showWakePrerequisiteFeedback() {
        prerequisiteResetTask?.cancel()
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.35)) {
            lidPrerequisiteFeedback.activate(reduceMotion: reduceMotion)
        }
        prerequisiteResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                lidPrerequisiteFeedback.reset()
            }
        }
    }

    private var safetyMessage: String? {
        switch controller.state.safetyStatus {
        case .normal:
            return controller.state.isLidModeEnabled ? L10n.text("safety.active", language: language) : nil
        case .helperApprovalRequired:
            return L10n.text("safety.approval", language: language)
        case .helperUnavailable:
            return L10n.text("safety.helperUnavailable", language: language)
        case .lowBattery:
            return L10n.text("safety.lowBattery", language: language)
        case .thermalPressure:
            return L10n.text("safety.thermal", language: language)
        case .unsupportedHardware:
            return L10n.text("lid.unavailable", language: language)
        }
    }

    private var quickAwayRowTitle: String {
        if controller.state.sessionSource == .quickAway {
            return L10n.text(
                controller.state.quickAway.copyStyle == .aquaticResearch
                    ? "quickAway.aquatic.active"
                    : "quickAway.cyber.active",
                language: language
            )
        }
        return L10n.text(
            controller.state.quickAway.copyStyle == .aquaticResearch
                ? "quickAway.aquatic.start"
                : "quickAway.cyber.start",
            language: language
        )
    }

    private var quickAwayRowDetail: String {
        if controller.state.sessionSource == .quickAway {
            return controller.remainingText
        }
        return String(
            format: L10n.text("quickAway.defaultDetail", language: language),
            controller.state.quickAway.durationMinutes,
            controller.state.quickAway.brightnessStep
        )
    }

    private var quickAwayStartButtonTitle: String {
        L10n.text("quickAway.open", language: language)
    }

    private var quickAwayReturnTitle: String {
        L10n.text(
            controller.state.quickAway.copyStyle == .aquaticResearch
                ? "quickAway.aquatic.return"
                : "quickAway.cyber.return",
            language: language
        )
    }

    private var quickAwayConfirmationTitle: String {
        L10n.text(
            controller.state.quickAway.copyStyle == .aquaticResearch
                ? "quickAway.aquatic.confirmTitle"
                : "quickAway.cyber.confirmTitle",
            language: language
        )
    }

    private var quickAwayConfirmationBody: String {
        String(
            format: L10n.text(
                controller.state.quickAway.copyStyle == .aquaticResearch
                    ? "quickAway.aquatic.confirmBody"
                    : "quickAway.cyber.confirmBody",
                language: language
            ),
            controller.state.quickAway.durationMinutes,
            controller.state.quickAway.brightnessStep
        )
    }

    private var quickAwayConfirmTitle: String {
        L10n.text(
            controller.state.quickAway.copyStyle == .aquaticResearch
                ? "quickAway.aquatic.confirm"
                : "quickAway.cyber.confirm",
            language: language
        )
    }

    private var quickAwayCancelTitle: String {
        L10n.text(
            controller.state.quickAway.copyStyle == .aquaticResearch
                ? "quickAway.aquatic.cancel"
                : "quickAway.cyber.cancel",
            language: language
        )
    }
}

struct CustomDurationEditorState: Equatable {
    private(set) var isPresented = false
    private(set) var originalMinutes = 90
    var draftMinutes = 90

    mutating func present(currentMinutes: Int) {
        let minutes = Self.clamped(currentMinutes)
        originalMinutes = minutes
        draftMinutes = minutes
        isPresented = true
    }

    mutating func toggle(currentMinutes: Int) {
        if isPresented {
            cancel()
        } else {
            present(currentMinutes: currentMinutes)
        }
    }

    mutating func cancel() {
        draftMinutes = originalMinutes
        isPresented = false
    }

    mutating func apply() -> Int? {
        guard isPresented else { return nil }
        let minutes = Self.clamped(draftMinutes)
        originalMinutes = minutes
        draftMinutes = minutes
        isPresented = false
        return minutes
    }

    private static func clamped(_ minutes: Int) -> Int {
        min(1_440, max(1, minutes))
    }
}

struct LidPrerequisiteFeedbackState: Equatable {
    private(set) var isEmphasized = false
    private(set) var shakeIteration = 0

    mutating func activate(reduceMotion: Bool) {
        isEmphasized = true
        if !reduceMotion {
            shakeIteration += 1
        }
    }

    mutating func reset() {
        isEmphasized = false
    }
}

enum LidInteractionPolicy {
    enum Activation: Equatable {
        case unavailable
        case showWakePrerequisite
        case requestConfirmation
    }

    static func activation(hasClamshell: Bool, isAwake: Bool) -> Activation {
        guard hasClamshell else { return .unavailable }
        guard isAwake else { return .showWakePrerequisite }
        return .requestConfirmation
    }
}

private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 3
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: travel * sin(animatableData * .pi * shakes * 2),
                y: 0
            )
        )
    }
}
