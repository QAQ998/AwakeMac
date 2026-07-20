import XCTest

final class HardwareCapabilitiesTests: XCTestCase {
    func testPortableHardwareIsDetectedFromPublicClamshellProperty() {
        let detector = HardwareCapabilityDetector(
            propertyReader: { key in
                if key == "AppleClamshellState" { return false }
                if key == "IOSleepSupported" { return true }
                return nil
            },
            modelIdentifier: { "MacBookAir10,1" }
        )
        let capabilities = detector.detect()
        XCTAssertTrue(capabilities.hasClamshell)
        XCTAssertEqual(capabilities.clamshell, .supported(isClosed: false))
    }

    func testDesktopHardwareIsDisabledWhenClamshellPropertyIsAbsent() {
        let detector = HardwareCapabilityDetector(
            propertyReader: { key in key == "IOSleepSupported" ? true : nil },
            modelIdentifier: { "Macmini9,1" }
        )
        let capabilities = detector.detect()
        XCTAssertFalse(capabilities.hasClamshell)
        XCTAssertEqual(capabilities.clamshell, .unavailable)
    }

    func testQueryFailureFailsClosed() {
        let detector = HardwareCapabilityDetector(
            propertyReader: { _ in nil },
            modelIdentifier: { "Unknown Mac" }
        )
        let capabilities = detector.detect()
        XCTAssertFalse(capabilities.hasClamshell)
        XCTAssertEqual(capabilities.clamshell, .queryFailed)
    }
}

