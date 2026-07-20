import SwiftUI
import WidgetKit

struct AwakeEntry: TimelineEntry {
    let date: Date
    let state: WakeState
}

struct AwakeProvider: TimelineProvider {
    private let store = SharedStateStore()

    func placeholder(in context: Context) -> AwakeEntry {
        var state = WakeState()
        state.start(duration: .oneHour)
        state.hardwareHasClamshell = true
        return AwakeEntry(date: .now, state: state)
    }

    func getSnapshot(in context: Context, completion: @escaping (AwakeEntry) -> Void) {
        completion(AwakeEntry(date: .now, state: store.loadState()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AwakeEntry>) -> Void) {
        let state = store.loadState()
        let entry = AwakeEntry(date: .now, state: state)
        let nextRefresh: Date
        if state.isAwakeEnabled, let endAt = state.endAt {
            nextRefresh = min(endAt, Date.now.addingTimeInterval(60))
        } else {
            nextRefresh = Date.now.addingTimeInterval(15 * 60)
        }
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct AwakeMacWidget: Widget {
    let kind = "AwakeMacWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AwakeProvider()) { entry in
            AwakeWidgetView(entry: entry)
        }
        .configurationDisplayName("AwakeMac")
        .description("Control and view the current wake session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct AwakeMacWidgetBundle: WidgetBundle {
    var body: some Widget {
        AwakeMacWidget()
    }
}

private struct AwakeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AwakeEntry

    private var language: AppLanguage { .systemDefault }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumView
            } else {
                smallView
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .environment(\.locale, language.locale)
        .modifier(WidgetTextSizeModifier())
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                L10n.text("widget.name", language: language),
                systemImage: entry.state.isAwakeEnabled ? "sun.max.fill" : "moon.zzz"
            )
            .font(.headline)
            .foregroundStyle(entry.state.isAwakeEnabled ? Color.green : Color.primary)
            .widgetAccentable()

            Spacer(minLength: 4)
            Text(remainingText)
                .font(.title2.weight(.semibold))
                .minimumScaleFactor(0.75)
                .lineLimit(2)
            Text(sessionDetailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(intent: ToggleWakeIntent()) {
                Text(L10n.text(entry.state.isAwakeEnabled ? "widget.stop" : "widget.start", language: language))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(entry.state.isAwakeEnabled ? .secondary : .accentColor)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    L10n.text("widget.name", language: language),
                    systemImage: entry.state.isAwakeEnabled ? "sun.max.fill" : "moon.zzz"
                )
                .font(.headline)
                .foregroundStyle(entry.state.isAwakeEnabled ? Color.green : Color.primary)
                Text(remainingText)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text(sessionDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(lidText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                quickButton(label: durationLabel(30), minutes: 30)
                quickButton(label: durationLabel(60), minutes: 60)
                quickButton(label: L10n.text("duration.unlimited", language: language), minutes: 0)
                Button(intent: StopWakeIntent()) {
                    Text(L10n.text("widget.stop", language: language)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
                .disabled(!entry.state.isAwakeEnabled)
            }
            .frame(width: 104)
        }
    }

    private func quickButton(label: String, minutes: Int) -> some View {
        Button(intent: StartWakeIntent(minutes: minutes)) {
            Text(label).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(entry.state.sessionSource == .quickAway)
    }

    private var sessionDetailText: String {
        guard entry.state.isAwakeEnabled else {
            return L10n.text("widget.systemSettings", language: language)
        }
        switch entry.state.sessionSource {
        case .manual:
            return L10n.text("wake.title", language: language)
        case .appAutomation:
            guard let name = entry.state.appAutomation.targetAppName else {
                return L10n.text("widget.automation", language: language)
            }
            return String(
                format: L10n.text("widget.automationApp", language: language),
                name
            )
        case .quickAway:
            return L10n.text(
                "widget.quickAway.\(entry.state.quickAway.copyStyle.localizationKeySegment)",
                language: language
            )
        }
    }

    private var remainingText: String {
        guard entry.state.isAwakeEnabled else { return L10n.text("status.off", language: language) }
        guard let endAt = entry.state.endAt else { return L10n.text("duration.unlimited", language: language) }
        let seconds = max(0, Int(endAt.timeIntervalSince(entry.date)))
        if seconds < 3_600 {
            return String(format: L10n.text("remaining.minutes", language: language), max(1, Int(ceil(Double(seconds) / 60))))
        }
        return String(
            format: L10n.text("remaining.hoursMinutes", language: language),
            seconds / 3_600,
            (seconds % 3_600) / 60
        )
    }

    private var lidText: String {
        if entry.state.hardwareHasClamshell == false {
            return L10n.text("widget.lid.noLid", language: language)
        }
        return L10n.text(entry.state.isLidModeEnabled ? "widget.lid.active" : "widget.lid.off", language: language)
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return String(format: L10n.text("duration.minutes", language: language), minutes) }
        return String(format: L10n.text("duration.hours", language: language), minutes / 60)
    }
}

private struct WidgetTextSizeModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var currentSize

    func body(content: Content) -> some View {
        content.dynamicTypeSize(nextSize(after: currentSize))
    }

    private func nextSize(after size: DynamicTypeSize) -> DynamicTypeSize {
        switch size {
        case .xSmall: .small
        case .small: .medium
        case .medium: .large
        case .large: .xLarge
        case .xLarge: .xxLarge
        case .xxLarge: .xxxLarge
        case .xxxLarge: .accessibility1
        case .accessibility1: .accessibility2
        case .accessibility2: .accessibility3
        case .accessibility3: .accessibility4
        case .accessibility4: .accessibility5
        case .accessibility5: .accessibility5
        @unknown default: size
        }
    }
}
