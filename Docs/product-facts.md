# AwakeMac product facts

- Target machine: Apple M1 MacBook Air (`MacBookAir10,1`) running macOS 26.4 with Xcode 26.4 and Swift 6.3.
- Standard SwiftUI, AppKit, and WidgetKit controls automatically adopt the current macOS visual language, including Liquid Glass where the system applies it.
- `ProcessInfo.ActivityOptions.idleDisplaySleepDisabled` keeps the display powered and `idleSystemSleepDisabled` prevents idle system sleep while the owning process remains alive.
- The public IOKit header documents `AppleClamshellState`: present on portable hardware and absent on hardware without a clamshell.
- WidgetKit widgets on macOS support focused App Intent interactions but do not own a durable process that can hold a power assertion indefinitely. The menu bar app remains the source of truth.
- `SMAppService.daemon(plistName:)` requires a signed and notarized app for the production approval flow. The personal local build instead installs a fixed root-owned LaunchDaemon after an explicit administrator prompt and pairs it to the current app’s exact code requirement.
- `/usr/bin/pmset` on this machine contains the `disablesleep` capability, but Apple does not document it as a stable public interface. AwakeMac treats it as experimental and fail-safe.

Primary references:

- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/design/human-interface-guidelines/widgets
- https://developer.apple.com/documentation/foundation/processinfo/activityoptions/idledisplaysleepdisabled
- https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:)
- `/Applications/Xcode.app/.../IOKit.framework/Headers/pwr_mgt/IOPM.h`
