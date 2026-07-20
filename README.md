# AwakeMac / 醒着

AwakeMac is a native macOS 14–26 menu bar utility that keeps the display and system awake without changing the user's original idle-sleep timers. It includes an interactive desktop widget, system-language Chinese/English UI, hardware capability detection, countdowns, a low-brightness quick-break session, and an experimental closed-lid helper with fail-safe leases. Release builds are Universal 2 and run natively on Apple Silicon and Intel Macs.

The direct-launch build opens a compact native control window when double-clicked and also remains available from the menu bar. Closing the control window does not quit the utility; double-clicking the app again restores the window.

Version 1.2.1 refines the Quick Break experience:

- All semantic text styles render one system size larger while continuing to respect the user's accessibility text-size preference.
- Duration uses common presets and brightness uses a native slider with familiar sun controls.
- Quick Break temporarily replaces the current session, lowers supported displays to a configured 1/64–64/64 brightness step, and restores brightness when the session ends. Its UI copy can switch between “Field Research / 水产调研” and “Cyber Cover / 赛博托管”. Hover the info icon in Settings for an in-app explanation.
- App Link is temporarily hidden while its interaction is refined. A previously enabled App Link preference is disabled on launch so no invisible automation remains active.

## Open and build

Runtime support: macOS 14 through macOS 26. This checkout is built with Swift 6, Xcode 26.4, and XcodeGen 2.46 or later; all targets use a macOS 14 deployment target.

```bash
cd /path/to/AwakeMac
xcodegen generate
open AwakeMac.xcodeproj
```

For a compile-only unsigned verification:

```bash
zsh Scripts/build-debug.sh
```

The script writes build products to `.derivedData` inside the project.

## Direct local use

1. Open `AwakeMac.app` and turn on normal Stay Awake mode.
2. Turn on “Stay awake with lid closed” and accept the safety warning.
3. On first use, macOS asks once for an administrator password. AwakeMac installs its local helper into `/Library/PrivilegedHelperTools` and `/Library/LaunchDaemons`.
4. The local build does not use the “Allow in the Background” list. After installation, the lid control becomes available immediately.

The installer pairs the root helper with the exact code requirement of the current app build. If the app binary changes, AwakeMac reports “Update required” and requests administrator authorization once to update that pairing.

## Signing for development

1. Open `AwakeMac.xcodeproj` in Xcode.
2. Select the `AwakeMac` and `AwakeMacWidget` targets and choose a valid Personal Team under Signing & Capabilities.
3. Ensure both targets contain the App Group `group.com.zhuhai.AwakeMac`. If Xcode requires a unique identifier, change the bundle identifiers and App Group consistently in `project.yml`, entitlements, and `SharedStateStore.swift`, then regenerate the project.
4. Build and copy `AwakeMac.app` to a stable location before installing the privileged helper.
5. Launch AwakeMac. The normal wake mode and timers work without the helper.

## Experimental closed-lid helper

- Closed-lid mode is shown only when the public IOKit `AppleClamshellState` property is present. Desktop Macs and failed capability queries remain disabled.
- The personal local build installs `PowerHelper` with an administrator-authorized installer. It uses fixed root-owned paths and never accepts a caller that does not match the paired app code requirement.
- The helper accepts only the fixed `pmset -a disablesleep 1/0` operation. It uses a 90-second lease renewed every 30 seconds and restores lid sleep after a crash, timeout, restart marker, low battery, or thermal pressure.
- A future distributed build should use Developer ID signing, notarization, and `SMAppService`. The local installer exists only for this personal-machine build. Normal wake mode and widgets do not depend on it.
- Do not place a closed, awake MacBook in a bag. The 20% battery and thermal guards are intentionally not configurable.

## Verification

```bash
xcodebuild -project AwakeMac.xcodeproj -scheme AwakeMac -destination 'platform=macOS,arch=arm64' -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AwakeMac.xcodeproj -scheme AwakeMac -destination 'platform=macOS,arch=arm64' -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO test
pmset -g assertions
pmset -g custom
```

The UI prototype is available at `Prototype/AwakeMac UI Prototype.html`; it can simulate language, appearance, MacBook/Mac mini capability, timers, widgets, and the first-use safety warning.

## License and copyright

Copyright © 2026 QAQ998. AwakeMac is released under the [MIT License](LICENSE). Reuse and modification are allowed, but the copyright and license notice must be preserved in copies or substantial portions of the software.

## Safety and uninstall

Use Settings → Safety → Remove Helper before deleting the app. Removal restores `disablesleep 0` before unloading the daemon.

If the app was deleted unexpectedly, first restore lid sleep:

```bash
sudo pmset -a disablesleep 0
```

Then remove only these fixed local-helper files and unload `system/com.zhuhai.AwakeMac.PowerHelper`; the app’s bundled installer performs those steps automatically when available.
