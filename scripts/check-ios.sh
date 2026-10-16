#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode_16.4.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "Full Xcode 16.4 is required. Install it and set DEVELOPER_DIR to its Contents/Developer directory." >&2
  exit 1
fi
version="$(xcodebuild -version)"
if [[ "$version" != $'Xcode 16.4\nBuild version 16F6' ]]; then
  echo "Expected Xcode 16.4 (16F6); found: $version" >&2
  exit 1
fi
xcodebuild -version
xcodebuild -project WardrobeAI.xcodeproj -scheme WardrobeAI \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5,arch=arm64' \
  -derivedDataPath DerivedData -resultBundlePath build/M00.xcresult \
  CODE_SIGNING_ALLOWED=NO clean build test
