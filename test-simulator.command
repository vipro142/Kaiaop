#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Boot the desired iPhone/iPad simulator in Xcode first.
xcodebuild -project LivePro.xcodeproj -scheme LivePro -configuration Debug -destination "platform=iOS Simulator,id=${SIMULATOR_UDID:?Set SIMULATOR_UDID from xcrun simctl list devices available}" CODE_SIGNING_ALLOWED=NO test
