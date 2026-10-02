#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project LivePro.xcodeproj -scheme LivePro -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
mkdir -p build/unsigned/Payload
 ditto build/DerivedData/Build/Products/Release-iphoneos/LivePro.app build/unsigned/Payload/LivePro.app
(cd build/unsigned && /usr/bin/zip -qr ../LIVEPRO-Intercom-unsigned.ipa Payload)
echo 'Created build/LIVEPRO-Intercom-unsigned.ipa. Must be signed before installation.'
