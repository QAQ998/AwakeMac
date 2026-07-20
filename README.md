# AwakeMac / 醒着

AwakeMac（醒着）是一款原生 macOS 菜单栏小工具，用来阻止电脑自动息屏和空闲睡眠。关闭保持唤醒后，电脑会继续使用原来的系统睡眠设置。

[下载最新正式版](https://github.com/QAQ998/AwakeMac/releases/latest)

## 主要功能

- 无限期或按指定时长保持唤醒
- “离开一会”：保持唤醒、临时降低屏幕亮度，结束后自动恢复
- 实验性的合盖运行模式，包含安全租约、低电量和温度保护
- 自动识别 MacBook 与无盖桌面 Mac
- 菜单栏控制和桌面小组件
- 简体中文与英文界面
- Universal 2，同时支持 Apple Silicon 和 Intel Mac

## 安装

1. 从 [Releases](https://github.com/QAQ998/AwakeMac/releases/latest) 下载 DMG。
2. 打开 DMG，将 `AwakeMac.app` 拖入“应用程序”。
3. 首次启动时，在“应用程序”中右键 AwakeMac，选择“打开”，再确认一次。

当前公开版本尚未使用 Developer ID 完成 Apple 公证，因此首次打开需要手动确认。普通保持唤醒不需要管理员权限；首次使用“合盖仍保持运行”时，系统会要求管理员授权安装安全助手。

系统要求：macOS 14 或更高版本。

## 从源码构建

需要 Swift 6、Xcode 26.4 和 XcodeGen：

```bash
xcodegen generate
open AwakeMac.xcodeproj
```

---

## English

AwakeMac is a native macOS menu bar utility that prevents idle display and system sleep without changing your original Energy settings. Turning it off restores normal system behavior.

Features include timed or unlimited wake sessions, a low-brightness “Step Away” mode, an experimental fail-safe closed-lid mode, desktop widgets, hardware capability detection, Chinese and English UI, and Universal 2 support for Apple Silicon and Intel Macs.

### Install

1. Download the DMG from [Releases](https://github.com/QAQ998/AwakeMac/releases/latest).
2. Drag `AwakeMac.app` to Applications.
3. On first launch, Control-click AwakeMac in Applications, choose Open, and confirm once.

This open-source build is not yet notarized with an Apple Developer ID. Normal wake mode requires no administrator access; closed-lid mode requests administrator authorization once to install its safety helper.

Requires macOS 14 or later.

## License

Copyright © 2026 QAQ998. Released under the [MIT License](LICENSE).
