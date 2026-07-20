import AppKit

@MainActor
protocol ApplicationRunningDetecting: AnyObject {
    func isRunning(bundleIdentifier: String) -> Bool
}

@MainActor
final class WorkspaceApplicationRunningDetector: ApplicationRunningDetecting {
    func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
