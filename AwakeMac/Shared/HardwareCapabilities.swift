import Foundation
import IOKit

struct HardwareCapabilities: Equatable, Sendable {
    enum ClamshellSupport: Equatable, Sendable {
        case supported(isClosed: Bool)
        case unavailable
        case queryFailed
    }

    let modelIdentifier: String
    let clamshell: ClamshellSupport

    var hasClamshell: Bool {
        if case .supported = clamshell { return true }
        return false
    }

    var diagnostic: String {
        switch clamshell {
        case .supported(let isClosed): "\(modelIdentifier): clamshell present, closed=\(isClosed)"
        case .unavailable: "\(modelIdentifier): AppleClamshellState is absent"
        case .queryFailed: "\(modelIdentifier): unable to query IOPMrootDomain"
        }
    }
}

struct HardwareCapabilityDetector: Sendable {
    typealias PropertyReader = @Sendable (String) -> Any?

    private let propertyReader: PropertyReader
    private let modelIdentifier: @Sendable () -> String

    init(
        propertyReader: @escaping PropertyReader = HardwareCapabilityDetector.readPowerProperty,
        modelIdentifier: @escaping @Sendable () -> String = HardwareCapabilityDetector.readModelIdentifier
    ) {
        self.propertyReader = propertyReader
        self.modelIdentifier = modelIdentifier
    }

    func detect() -> HardwareCapabilities {
        let model = modelIdentifier()
        guard let value = propertyReader("AppleClamshellState") else {
            // A reachable root domain with no key is the public signal for hardware without a lid.
            if propertyReader("IOSleepSupported") != nil {
                return HardwareCapabilities(modelIdentifier: model, clamshell: .unavailable)
            }
            return HardwareCapabilities(modelIdentifier: model, clamshell: .queryFailed)
        }

        if let closed = value as? Bool {
            return HardwareCapabilities(modelIdentifier: model, clamshell: .supported(isClosed: closed))
        }
        if let number = value as? NSNumber {
            return HardwareCapabilities(modelIdentifier: model, clamshell: .supported(isClosed: number.boolValue))
        }
        return HardwareCapabilities(modelIdentifier: model, clamshell: .queryFailed)
    }

    static func readPowerProperty(_ key: String) -> Any? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func readModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Unknown Mac" }
        let content = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: content, as: UTF8.self)
    }
}
