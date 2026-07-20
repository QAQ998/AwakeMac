#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/AwakeMac.app" >&2
  exit 2
fi

app_path="$1"
executable_path="$app_path/Contents/MacOS/AwakeMac"

if [[ ! -x "$executable_path" ]]; then
  echo "FAIL: missing executable at $executable_path" >&2
  exit 2
fi

pkill -TERM -f "$executable_path" 2>/dev/null || true
open -n "$app_path"
sleep 2

if ! pgrep -f "$executable_path" >/dev/null; then
  echo "FAIL: AwakeMac did not stay running" >&2
  exit 1
fi

swift - <<'SWIFT'
import CoreGraphics
import Foundation

let windows = (CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]]) ?? []

let visibleWindows = windows.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "AwakeMac"
        && (($0[kCGWindowLayer as String] as? Int) ?? -1) == 0
}

guard !visibleWindows.isEmpty else {
    fputs("FAIL: AwakeMac is running but has no visible control window\n", stderr)
    exit(1)
}

print("PASS: AwakeMac launched with \(visibleWindows.count) visible control window(s)")
SWIFT
