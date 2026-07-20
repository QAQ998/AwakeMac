import SwiftUI

@main
struct AwakeMacApp: App {
    @NSApplicationDelegateAdaptor(AwakeMacAppDelegate.self) private var appDelegate
    @StateObject private var controller: WakeController

    init() {
        let controller = WakeController()
        _controller = StateObject(wrappedValue: controller)
        controller.start()
    }

    var body: some Scene {
        WindowGroup {
            MenuBarContentView(presentation: .mainWindow)
                .environmentObject(controller)
                .environment(\.locale, controller.state.language.locale)
                .background(MainWindowMarker())
        }
        .defaultSize(width: 340, height: 360)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView(presentation: .menuBar)
                .environmentObject(controller)
                .environment(\.locale, controller.state.language.locale)
                .background(MenuBarWindowMarker())
        } label: {
            Image(systemName: controller.state.isAwakeEnabled ? "sun.max.fill" : "moon.zzz")
                .accessibilityLabel(controller.state.isAwakeEnabled ? "AwakeMac active" : "AwakeMac off")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(controller)
                .environment(\.locale, controller.state.language.locale)
                .frame(minWidth: 520, minHeight: 420)
                .background(SettingsWindowMarker())
        }
    }
}
