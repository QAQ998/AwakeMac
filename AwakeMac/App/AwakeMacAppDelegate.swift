import AppKit
import SwiftUI

@MainActor
final class AwakeMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.showMainWindow(in: NSApplication.shared)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showMainWindow(in: sender)
        } else {
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }

    private func showMainWindow(in application: NSApplication) {
        AppWindowCoordinator.showMainControlWindow()
    }
}

struct MainWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowMarkerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowMarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = AppWindowCoordinator.mainWindowIdentifier
            window?.isReleasedWhenClosed = false
        }
    }
}
