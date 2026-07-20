import AppKit
import XCTest
@testable import AwakeMac

@MainActor
final class AppWindowCoordinatorTests: XCTestCase {
    private static var retainedWindows: [NSWindow] = []

    private func retainForTestLifetime(_ windows: NSWindow...) {
        windows.forEach {
            $0.isReleasedWhenClosed = false
            Self.retainedWindows.append($0)
        }
    }

    private func clearCoordinatorWindowIdentifiers() {
        NSApp.windows
            .filter {
                $0.identifier == AppWindowCoordinator.mainWindowIdentifier
                    || $0.identifier == AppWindowCoordinator.menuBarWindowIdentifier
            }
            .forEach {
                $0.orderOut(nil)
                $0.identifier = nil
            }
    }

    func testMenuBarControlHidesVisibleMainWindow() {
        clearCoordinatorWindowIdentifiers()
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        mainWindow.identifier = AppWindowCoordinator.mainWindowIdentifier
        mainWindow.animationBehavior = .none
        retainForTestLifetime(mainWindow)
        mainWindow.orderFrontRegardless()
        defer { mainWindow.close() }

        XCTAssertTrue(mainWindow.isVisible)

        AppWindowCoordinator.menuBarControlDidAppear()

        XCTAssertFalse(mainWindow.isVisible)
    }

    func testReactivatedMenuBarPanelHidesMainWindow() async {
        clearCoordinatorWindowIdentifiers()
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        mainWindow.identifier = AppWindowCoordinator.mainWindowIdentifier
        mainWindow.animationBehavior = .none

        let menuPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        menuPanel.animationBehavior = .none
        menuPanel.level = .popUpMenu
        menuPanel.contentView = MenuBarWindowMarker.WindowMarkerView()
        retainForTestLifetime(mainWindow, menuPanel)
        defer {
            menuPanel.close()
            mainWindow.close()
        }

        menuPanel.orderFrontRegardless()
        mainWindow.orderFrontRegardless()
        XCTAssertTrue(menuPanel.isVisible)
        XCTAssertTrue(mainWindow.isVisible)

        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: menuPanel
        )
        await Task.yield()

        XCTAssertTrue(menuPanel.isVisible)
        XCTAssertFalse(mainWindow.isVisible)
    }

    func testMenuBarFlowStaysInlineWithoutOpeningMainWindow() async {
        clearCoordinatorWindowIdentifiers()
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        mainWindow.identifier = AppWindowCoordinator.mainWindowIdentifier
        mainWindow.animationBehavior = .none

        let transientPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        transientPanel.identifier = NSUserInterfaceItemIdentifier("AwakeMacMenuBarWindow")
        transientPanel.animationBehavior = .none
        transientPanel.level = .popUpMenu
        retainForTestLifetime(mainWindow, transientPanel)
        transientPanel.makeKeyAndOrderFront(nil)
        defer {
            transientPanel.close()
            mainWindow.close()
        }

        var continuationCount = 0
        let handoffFinished = expectation(description: "Handoff finished")
        AppWindowCoordinator.continueMenuBarFlowInline {
            continuationCount += 1
            handoffFinished.fulfill()
        }
        await fulfillment(of: [handoffFinished], timeout: 3)

        XCTAssertTrue(transientPanel.isVisible)
        XCTAssertFalse(mainWindow.isVisible)
        XCTAssertEqual(continuationCount, 1)
    }

    func testInlineMenuBarFlowDoesNotCloseUnrelatedPanels() async {
        clearCoordinatorWindowIdentifiers()
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        mainWindow.identifier = AppWindowCoordinator.mainWindowIdentifier
        mainWindow.animationBehavior = .none

        let menuPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        menuPanel.identifier = NSUserInterfaceItemIdentifier("AwakeMacMenuBarWindow")
        menuPanel.animationBehavior = .none
        menuPanel.level = .popUpMenu
        menuPanel.orderFrontRegardless()

        let unrelatedPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        unrelatedPanel.level = .floating
        unrelatedPanel.animationBehavior = .none
        unrelatedPanel.orderFrontRegardless()
        retainForTestLifetime(mainWindow, menuPanel, unrelatedPanel)

        defer {
            menuPanel.close()
            unrelatedPanel.close()
            mainWindow.close()
        }

        let handoffFinished = expectation(description: "Handoff finished")
        AppWindowCoordinator.continueMenuBarFlowInline {
            handoffFinished.fulfill()
        }
        await fulfillment(of: [handoffFinished], timeout: 3)

        XCTAssertTrue(menuPanel.isVisible)
        XCTAssertFalse(mainWindow.isVisible)
        XCTAssertTrue(unrelatedPanel.isVisible)
    }
}
