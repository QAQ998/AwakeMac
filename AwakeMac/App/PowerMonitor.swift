import Foundation
import IOKit.ps

struct PowerSnapshot: Equatable, Sendable {
    let isOnBattery: Bool
    let batteryPercent: Int?
}

enum PowerMonitor {
    static func snapshot() -> PowerSnapshot {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return PowerSnapshot(isOnBattery: false, batteryPercent: nil) }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            let powerState = description[kIOPSPowerSourceStateKey] as? String
            let percent = current.flatMap { value in maximum.flatMap { $0 > 0 ? Int((Double(value) / Double($0) * 100).rounded()) : nil } }
            return PowerSnapshot(isOnBattery: powerState == kIOPSBatteryPowerValue, batteryPercent: percent)
        }

        return PowerSnapshot(isOnBattery: false, batteryPercent: nil)
    }
}

