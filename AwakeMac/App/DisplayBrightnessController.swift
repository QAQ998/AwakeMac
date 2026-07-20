import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.graphics

struct BrightnessAdjustmentResult: Equatable, Sendable {
    let adjustedDisplayCount: Int
    let unsupportedDisplayCount: Int

    var didAdjustAnyDisplay: Bool { adjustedDisplayCount > 0 }
}

struct BrightnessRestoreResult: Equatable, Sendable {
    let restoredDisplayCount: Int
    let failedDisplayCount: Int
}

@MainActor
protocol DisplayBrightnessServicing: AnyObject {
    func canAdjustAnyDisplay() -> Bool
    func applyTemporaryBrightness(step: Int) -> BrightnessAdjustmentResult
    func restoreTemporaryBrightness() -> BrightnessRestoreResult
}

@MainActor
final class DisplayBrightnessController: DisplayBrightnessServicing {
    private enum Backend: String, Codable {
        case displayServices
        case ioKit
    }

    private struct Snapshot: Codable, Equatable {
        let backend: Backend
        let identifier: String
        let originalBrightness: Float
        let appliedBrightness: Float
    }

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let recoveryKey = "quickAway.brightnessRecovery.v1"
    private static let brightnessKey = "brightness" as CFString
    private static let comparisonTolerance: Float = 0.02

    private let preferences: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let displayServicesHandle: UnsafeMutableRawPointer?
    private let getDisplayServicesBrightness: GetBrightness?
    private let setDisplayServicesBrightness: SetBrightness?

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences

        let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY | RTLD_LOCAL
        )
        displayServicesHandle = handle
        if let handle,
           let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
           let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") {
            getDisplayServicesBrightness = unsafeBitCast(getSymbol, to: GetBrightness.self)
            setDisplayServicesBrightness = unsafeBitCast(setSymbol, to: SetBrightness.self)
        } else {
            getDisplayServicesBrightness = nil
            setDisplayServicesBrightness = nil
        }
    }

    func canAdjustAnyDisplay() -> Bool {
        if displayServicesDisplays().contains(where: { display in
            guard let getDisplayServicesBrightness else { return false }
            var value: Float = 0
            return getDisplayServicesBrightness(display, &value) == 0
        }) {
            return true
        }

        return withIODisplayServices { service, _ in
            var value: Float = 0
            return IODisplayGetFloatParameter(
                service,
                IOOptionBits(0),
                Self.brightnessKey,
                &value
            ) == kIOReturnSuccess
        }
    }

    func applyTemporaryBrightness(step: Int) -> BrightnessAdjustmentResult {
        _ = restoreTemporaryBrightness()
        let target = Float(min(64, max(1, step))) / 64
        let onlineDisplays = displayServicesDisplays()
        var snapshots: [Snapshot] = []

        if let getDisplayServicesBrightness, let setDisplayServicesBrightness {
            for display in onlineDisplays {
                var original: Float = 0
                guard getDisplayServicesBrightness(display, &original) == 0 else { continue }
                guard setDisplayServicesBrightness(display, target) == 0 else { continue }

                var verified: Float = 0
                guard getDisplayServicesBrightness(display, &verified) == 0,
                      abs(verified - target) <= Self.comparisonTolerance else {
                    _ = setDisplayServicesBrightness(display, original)
                    continue
                }
                snapshots.append(
                    Snapshot(
                        backend: .displayServices,
                        identifier: displayIdentifier(display),
                        originalBrightness: original,
                        appliedBrightness: verified
                    )
                )
                saveSnapshots(snapshots)
            }
        }

        // DisplayServices covers built-in and Apple displays. Use the public IOKit
        // parameter path only when that native path did not control any display,
        // avoiding duplicate adjustments of the same panel.
        if snapshots.isEmpty {
            _ = withIODisplayServices { service, identifier in
                var original: Float = 0
                guard IODisplayGetFloatParameter(
                    service,
                    IOOptionBits(0),
                    Self.brightnessKey,
                    &original
                ) == kIOReturnSuccess else { return false }
                guard IODisplaySetFloatParameter(
                    service,
                    IOOptionBits(0),
                    Self.brightnessKey,
                    target
                ) == kIOReturnSuccess else { return false }

                var verified: Float = 0
                guard IODisplayGetFloatParameter(
                    service,
                    IOOptionBits(0),
                    Self.brightnessKey,
                    &verified
                ) == kIOReturnSuccess,
                      abs(verified - target) <= Self.comparisonTolerance else {
                    _ = IODisplaySetFloatParameter(
                        service,
                        IOOptionBits(0),
                        Self.brightnessKey,
                        original
                    )
                    return false
                }
                snapshots.append(
                    Snapshot(
                        backend: .ioKit,
                        identifier: identifier,
                        originalBrightness: original,
                        appliedBrightness: verified
                    )
                )
                saveSnapshots(snapshots)
                return true
            }
        }

        let onlineCount = max(onlineDisplays.count, snapshots.count)
        return BrightnessAdjustmentResult(
            adjustedDisplayCount: snapshots.count,
            unsupportedDisplayCount: max(0, onlineCount - snapshots.count)
        )
    }

    func restoreTemporaryBrightness() -> BrightnessRestoreResult {
        let snapshots = loadSnapshots()
        guard !snapshots.isEmpty else {
            return BrightnessRestoreResult(restoredDisplayCount: 0, failedDisplayCount: 0)
        }

        var restored = 0
        var unresolved: [Snapshot] = []
        let displayMap = Dictionary(
            uniqueKeysWithValues: displayServicesDisplays().map { (displayIdentifier($0), $0) }
        )

        for snapshot in snapshots {
            switch snapshot.backend {
            case .displayServices:
                guard let display = displayMap[snapshot.identifier],
                      let getDisplayServicesBrightness,
                      let setDisplayServicesBrightness else {
                    unresolved.append(snapshot)
                    continue
                }
                var current: Float = 0
                guard getDisplayServicesBrightness(display, &current) == 0 else {
                    unresolved.append(snapshot)
                    continue
                }
                // A user or automatic-brightness adjustment always wins.
                guard abs(current - snapshot.appliedBrightness) <= Self.comparisonTolerance else {
                    continue
                }
                if setDisplayServicesBrightness(display, snapshot.originalBrightness) == 0 {
                    restored += 1
                } else {
                    unresolved.append(snapshot)
                }

            case .ioKit:
                var matched = false
                let didRestore = withIODisplayServices { service, identifier in
                    guard identifier == snapshot.identifier else { return false }
                    matched = true
                    var current: Float = 0
                    guard IODisplayGetFloatParameter(
                        service,
                        IOOptionBits(0),
                        Self.brightnessKey,
                        &current
                    ) == kIOReturnSuccess else { return false }
                    guard abs(current - snapshot.appliedBrightness) <= Self.comparisonTolerance else {
                        return true
                    }
                    return IODisplaySetFloatParameter(
                        service,
                        IOOptionBits(0),
                        Self.brightnessKey,
                        snapshot.originalBrightness
                    ) == kIOReturnSuccess
                }
                if didRestore {
                    restored += 1
                } else if !matched {
                    unresolved.append(snapshot)
                } else {
                    unresolved.append(snapshot)
                }
            }
        }

        saveSnapshots(unresolved)
        return BrightnessRestoreResult(
            restoredDisplayCount: restored,
            failedDisplayCount: unresolved.count
        )
    }

    private func displayServicesDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private func displayIdentifier(_ display: CGDirectDisplayID) -> String {
        [
            CGDisplayVendorNumber(display),
            CGDisplayModelNumber(display),
            CGDisplaySerialNumber(display),
            CGDisplayUnitNumber(display)
        ]
        .map(String.init)
        .joined(separator: ":")
    }

    @discardableResult
    private func withIODisplayServices(
        _ body: (io_service_t, String) -> Bool
    ) -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        ) == kIOReturnSuccess else { return false }
        defer { IOObjectRelease(iterator) }

        var anySucceeded = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &registryID) == kIOReturnSuccess else { continue }
            if body(service, String(registryID)) {
                anySucceeded = true
            }
        }
        return anySucceeded
    }

    private func loadSnapshots() -> [Snapshot] {
        guard let data = preferences.data(forKey: Self.recoveryKey),
              let snapshots = try? decoder.decode([Snapshot].self, from: data) else { return [] }
        return snapshots
    }

    private func saveSnapshots(_ snapshots: [Snapshot]) {
        guard !snapshots.isEmpty else {
            preferences.removeObject(forKey: Self.recoveryKey)
            return
        }
        guard let data = try? encoder.encode(snapshots) else { return }
        preferences.set(data, forKey: Self.recoveryKey)
    }
}
