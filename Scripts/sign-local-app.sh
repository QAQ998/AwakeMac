#!/bin/zsh

set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  echo "usage: $0 /path/to/AwakeMac.app [codesign-identity]" >&2
  exit 64
fi

readonly app_bundle="${1:A}"
readonly signing_identity="${2:--}"
readonly script_directory="${0:A:h}"
readonly source_root="${script_directory:h}"
readonly helper_binary="$app_bundle/Contents/Library/LaunchDaemons/PowerHelper"
readonly widget_bundle="$app_bundle/Contents/PlugIns/AwakeMacWidget.appex"
readonly app_entitlements="$source_root/AwakeMac/AwakeMac.entitlements"
readonly widget_entitlements="$source_root/AwakeMacWidget/AwakeMacWidget.entitlements"

[[ -d "$app_bundle" ]] || { echo "missing app bundle: $app_bundle" >&2; exit 66; }
[[ -x "$helper_binary" ]] || { echo "missing helper binary: $helper_binary" >&2; exit 66; }
[[ -d "$widget_bundle" ]] || { echo "missing widget bundle: $widget_bundle" >&2; exit 66; }

# PowerHelper is a plain executable in Library/LaunchDaemons. `codesign --deep`
# does not discover it as nested code, so it must be signed explicitly before
# the widget and containing application are sealed.
/usr/bin/codesign --force --sign "$signing_identity" "$helper_binary"
/usr/bin/codesign --force --sign "$signing_identity" \
  --entitlements "$widget_entitlements" "$widget_bundle"
/usr/bin/codesign --force --sign "$signing_identity" \
  --entitlements "$app_entitlements" "$app_bundle"

/usr/bin/codesign --verify --strict --verbose=2 "$helper_binary"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"

echo "AwakeMac app, widget, and PowerHelper signatures are valid."
