#!/bin/zsh

set -euo pipefail

readonly release_version="${1:-1.0.0}"
readonly script_directory="${0:A:h}"
readonly source_root="${script_directory:h}"
readonly derived_data="$source_root/.releaseDerivedData"
readonly built_app="$derived_data/Build/Products/Release/AwakeMac.app"
readonly distribution_directory="$source_root/dist"
readonly disk_image_name="AwakeMac-v${release_version}-macOS-Universal.dmg"
readonly disk_image="$distribution_directory/$disk_image_name"
readonly checksum="$disk_image.sha256"
readonly first_launch_guide="$source_root/Docs/First Launch.txt"
typeset staging_directory=""

cleanup() {
  if [[ -n "$staging_directory" && "$staging_directory" == /tmp/AwakeMacRelease.* ]]; then
    /bin/rm -rf "$staging_directory"
  fi
}

trap cleanup EXIT

cd "$source_root"
command -v xcodegen >/dev/null || { echo "xcodegen is required" >&2; exit 69; }

xcodegen generate
/usr/bin/xcodebuild -quiet \
  -project AwakeMac.xcodeproj \
  -scheme AwakeMac \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$derived_data" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

readonly built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$built_app/Contents/Info.plist")"
[[ "$built_version" == "$release_version" ]] || {
  echo "built version $built_version does not match requested release $release_version" >&2
  exit 65
}

/bin/zsh "$source_root/Scripts/sign-local-app.sh" "$built_app"

/bin/mkdir -p "$distribution_directory"
/bin/rm -f "$disk_image" "$checksum"
staging_directory="$(/usr/bin/mktemp -d /tmp/AwakeMacRelease.XXXXXX)"
/usr/bin/ditto "$built_app" "$staging_directory/AwakeMac.app"
/bin/ln -s /Applications "$staging_directory/Applications"
/usr/bin/ditto "$first_launch_guide" "$staging_directory/First Launch · 首次打开.txt"

/usr/bin/hdiutil create \
  -volname "AwakeMac" \
  -srcfolder "$staging_directory" \
  -format UDZO \
  -ov \
  "$disk_image"
/usr/bin/hdiutil verify "$disk_image"

(
  cd "$distribution_directory"
  /usr/bin/shasum -a 256 "$disk_image_name" > "$disk_image_name.sha256"
)

echo "$disk_image"
echo "$checksum"
