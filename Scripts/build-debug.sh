#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

xcodegen generate
xcodebuild \
  -project AwakeMac.xcodeproj \
  -scheme AwakeMac \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Unsigned build: $PROJECT_DIR/.derivedData/Build/Products/Debug/AwakeMac.app"
