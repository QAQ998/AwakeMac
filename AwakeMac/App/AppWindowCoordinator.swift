import AppKit
import SwiftUI

@MainActor
enum AppWindowCoordinator {
    enum SharedErrorSurface {
        case mainControl
        case menuBar
        case settings
    }

    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("AwakeMacMainWindow")
    static let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("AwakeMacSettingsWindow")
    static let menuBarWindowIdentifier = NSUserInterfaceItemIdentifier("AwakeMacMenuBarWindow")

    static func menuBarControlDidAppear() {
        NSApp.windows
            .filter { $0.identifier == mainWindowIdentifier }
            .forEach { $0.orderOut(nil) }
    }

    static func shouldPresentSharedError(on surface: SharedErrorSurface) -> Bool {
        let menuBarWindow = NSApp.windows.first {
            $0.identifier == menuBarWindowIdentifier && $0.isVisible
        }
        if menuBarWindow != nil {
            return surface == .menuBar
        }

        if let keyWindow = NSApp.keyWindow {
            if keyWindow.identifier == settingsWindowIdentifier
                || keyWindow.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
                return surface == .settings
            }
            if keyWindow.identifier == mainWindowIdentifier {
                return surface == .mainControl
            }
        }

        let settingsWindowIsVisible = NSApp.windows.contains {
            ($0.identifier == settingsWindowIdentifier
                || $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window")
                && $0.isVisible
        }
        return settingsWindowIsVisible ? surface == .settings : surface == .mainControl
    }

    static func continueMenuBarFlowInline(_ continuation: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            continuation()
        }
    }

    @discardableResult
    static func showMainControlWindow() -> Bool {
        guard let mainWindow = NSApp.windows.first(where: {
            $0.identifier == mainWindowIdentifier
        }) else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow.level = .normal
        mainWindow.makeKeyAndOrderFront(nil)
        mainWindow.orderFrontRegardless()
        return true
    }

    static func openSettings(using openSettings: OpenSettingsAction) {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if bringSettingsWindowToFront() {
                dismissMenuBarControl()
                return
            }

            // SwiftUI may create the Settings scene on the following run-loop pass.
            DispatchQueue.main.async {
                if bringSettingsWindowToFront() {
                    dismissMenuBarControl()
                }
            }
        }
    }

    @discardableResult
    static func bringSettingsWindowToFront() -> Bool {
        guard let settingsWindow = NSApp.windows.first(where: {
            $0.identifier == settingsWindowIdentifier
                || $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
        }) else {
            return false
        }

        settingsWindow.level = .normal
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private static func dismissMenuBarControl() {
        NSApp.windows
            .filter { $0.identifier == menuBarWindowIdentifier }
            .forEach { $0.orderOut(nil) }
    }
}

struct MenuBarWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowMarkerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.window?.isVisible == true {
            AppWindowCoordinator.menuBarControlDidAppear()
        }
    }

    final class WindowMarkerView: NSView {
        private weak var observedWindow: NSWindow?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didBecomeKeyNotification,
                    object: observedWindow
                )
            }
            observedWindow = nil
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            window.identifier = AppWindowCoordinator.menuBarWindowIdentifier
            observedWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(menuBarWindowDidBecomeKey(_:)),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )

            if window.isVisible {
                AppWindowCoordinator.menuBarControlDidAppear()
            }
        }

        @objc private func menuBarWindowDidBecomeKey(_ notification: Notification) {
            AppWindowCoordinator.menuBarControlDidAppear()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

struct SettingsWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowMarkerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowMarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            window.identifier = AppWindowCoordinator.settingsWindowIdentifier
            window.isReleasedWhenClosed = false

            Task { @MainActor in
                AppWindowCoordinator.bringSettingsWindowToFront()
            }
        }
    }
}
