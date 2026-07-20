import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var controller: WakeController
    @State private var selectedTab = SettingsTab.general
    @State private var showsHelperRemovalConfirmation = false

    private var language: AppLanguage { controller.state.language }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label(L10n.text("settings.general", language: language), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            automationTab
                .tabItem { Label(L10n.text("settings.automation", language: language), systemImage: "bolt.badge.clock") }
                .tag(SettingsTab.automation)
            safetyTab
                .tabItem { Label(L10n.text("settings.safety", language: language), systemImage: "shield") }
                .tag(SettingsTab.safety)
            aboutTab
                .tabItem { Label(L10n.text("settings.about", language: language), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .padding(20)
        .awakeTextOneStepLarger()
        .alert(
            L10n.text("helper.remove.title", language: language),
            isPresented: $showsHelperRemovalConfirmation
        ) {
            Button(L10n.text("common.cancel", language: language), role: .cancel) {}
            Button(L10n.text("helper.remove.action", language: language), role: .destructive) {
                Task { await controller.uninstallLocalHelper() }
            }
        } message: {
            Text(L10n.text("helper.remove.body", language: language))
        }
        .alert(
            L10n.text("error.title", language: language),
            isPresented: Binding(
                get: {
                    controller.lastError != nil
                        && AppWindowCoordinator.shouldPresentSharedError(on: .settings)
                },
                set: { if !$0 { controller.lastError = nil } }
            )
        ) {
            Button(L10n.text("common.ok", language: language)) {
                controller.lastError = nil
            }
        } message: {
            Text(controller.lastError ?? "")
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle(
                    L10n.text("settings.launchAtLogin", language: language),
                    isOn: Binding(
                        get: { controller.loginItemEnabled },
                        set: { controller.setLoginItemEnabled($0) }
                    )
                )

                Picker(
                    L10n.text("settings.defaultDuration", language: language),
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

            }
        }
        .formStyle(.grouped)
    }

    private var safetyTab: some View {
        Form {
            Section(L10n.text("settings.hardware", language: language)) {
                LabeledContent(
                    L10n.text("settings.model", language: language),
                    value: controller.capabilities.modelDisplayName
                )
                LabeledContent(
                    L10n.text("settings.lidCapability", language: language),
                    value: controller.capabilities.hasClamshell
                        ? L10n.text("common.supported", language: language)
                        : L10n.text("common.unavailable", language: language)
                )
            }

            Section(L10n.text("settings.protection", language: language)) {
                LabeledContent {
                    Text(helperStatusText)
                } label: {
                    HStack(spacing: 5) {
                        Text(L10n.text("settings.helper", language: language))
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .help(L10n.text("helper.introduction", language: language))
                            .accessibilityLabel(
                                L10n.text("helper.introduction", language: language)
                            )
                    }
                }
                HStack {
                    Button(helperInstallButtonTitle) {
                        Task { _ = await controller.installLocalHelper() }
                    }
                    .disabled(controller.helperServiceStatus == .installing)

                    if controller.helperServiceStatus == .installed {
                        Button(L10n.text("helper.remove.action", language: language), role: .destructive) {
                            showsHelperRemovalConfirmation = true
                        }
                    }
                }
                LabeledContent(L10n.text("settings.batteryGuard", language: language), value: "20%")
                LabeledContent(
                    L10n.text("settings.thermalGuard", language: language),
                    value: L10n.text("settings.alwaysOn", language: language)
                )
            }

            Text(L10n.text("settings.experimentalNotice", language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var automationTab: some View {
        Form {
            Section {
                Picker(
                    L10n.text("quickAway.settings.copyStyle", language: language),
                    selection: Binding(
                        get: { controller.state.quickAway.copyStyle },
                        set: { controller.setQuickAwayCopyStyle($0) }
                    )
                ) {
                    Text(L10n.text("quickAway.style.brief", language: language))
                        .tag(QuickAwayCopyStyle.briefAway)
                    Text(L10n.text("quickAway.style.aquatic", language: language))
                        .tag(QuickAwayCopyStyle.aquaticResearch)
                    Text(L10n.text("quickAway.style.cyber", language: language))
                        .tag(QuickAwayCopyStyle.cyberCare)
                }

                Picker(
                    L10n.text("quickAway.settings.duration", language: language),
                    selection: Binding(
                        get: { controller.state.quickAway.durationMinutes },
                        set: { controller.setQuickAwayDuration(minutes: $0) }
                    )
                ) {
                    ForEach(quickAwayDurationOptions, id: \.self) { minutes in
                        Text(quickAwayDurationLabel(minutes)).tag(minutes)
                    }
                }

                LabeledContent(L10n.text("quickAway.settings.brightness", language: language)) {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.min")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Slider(
                            value: Binding(
                                get: { Double(controller.state.quickAway.brightnessLevel) },
                                set: { controller.setQuickAwayBrightnessLevel(Int($0.rounded())) }
                            ),
                            in: 1...10,
                            step: 1
                        )
                        .frame(minWidth: 150, idealWidth: 210, maxWidth: 260)
                        .controlSize(.large)
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("\(controller.state.quickAway.brightnessPercent)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                Text(L10n.text("quickAway.settings.detail", language: language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                HStack(spacing: 5) {
                    Text(L10n.text("quickAway.settings.section", language: language))
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .help(L10n.text("quickAway.settings.introduction", language: language))
                        .accessibilityLabel(
                            L10n.text("quickAway.settings.introduction", language: language)
                        )
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 46))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("AwakeMac")
                .font(.title2.weight(.semibold))
            Text(L10n.text("about.version", language: language))
                .foregroundStyle(.secondary)
            Text(L10n.text("about.description", language: language))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 330)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 28)
    }

    private var helperStatusText: String {
        switch controller.helperServiceStatus {
        case .installed: L10n.text("helper.enabled", language: language)
        case .installing: L10n.text("helper.installing", language: language)
        case .updateRequired: L10n.text("helper.updateRequired", language: language)
        case .notInstalled: L10n.text("helper.notInstalled", language: language)
        case .unavailable: L10n.text("helper.unknown", language: language)
        }
    }

    private var helperInstallButtonTitle: String {
        switch controller.helperServiceStatus {
        case .installed:
            L10n.text("helper.reinstall", language: language)
        case .updateRequired:
            L10n.text("helper.update", language: language)
        case .installing:
            L10n.text("helper.installing", language: language)
        case .notInstalled, .unavailable:
            L10n.text("helper.install", language: language)
        }
    }

    private func chooseAutomationApplication() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("automation.choosePanelTitle", language: language)
        panel.prompt = L10n.text("automation.choose", language: language)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                controller.selectAutomationApplication(at: url)
            }
        }
    }

    private func appExitGraceLabel(_ grace: AppExitGracePreset) -> String {
        switch grace {
        case .immediately:
            L10n.text("automation.grace.immediately", language: language)
        case .fiveMinutes, .tenMinutes, .thirtyMinutes:
            String(
                format: L10n.text("duration.minutes", language: language),
                grace.rawValue
            )
        }
    }

    private var quickAwayDurationOptions: [Int] {
        let presets = [5, 10, 15, 30, 45, 60, 90, 120, 180, 240]
        guard !presets.contains(controller.state.quickAway.durationMinutes) else {
            return presets
        }
        return (presets + [controller.state.quickAway.durationMinutes]).sorted()
    }

    private func quickAwayDurationLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return String(
                format: L10n.text("duration.minutes", language: language),
                minutes
            )
        }
        if minutes.isMultiple(of: 60) {
            return String(
                format: L10n.text("duration.hours", language: language),
                minutes / 60
            )
        }
        return String(
            format: L10n.text("duration.hoursMinutes", language: language),
            minutes / 60,
            minutes % 60
        )
    }
}

private enum SettingsTab: Hashable {
    case general
    case automation
    case safety
    case about
}
