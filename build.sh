#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/Owl.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build
ARCH="$(uname -m)"
xcrun swiftc -O -target "$ARCH-apple-macos13.0" -parse-as-library -import-objc-header Sources/PowerMessages.h Sources/Protocol.swift Sources/EventSources.swift Sources/PowerEvents.swift Sources/HelperSetup.swift Sources/LidDisplay.swift Sources/PowerPolicy.swift Sources/Helper.swift -o "$APP/Contents/Resources/com.yonigo.Owl.helper"
xcrun swiftc -O -target "$ARCH-apple-macos13.0" -parse-as-library Sources/Protocol.swift Sources/EventSources.swift Sources/OwlIcon.swift Sources/OwlApp.swift -o "$APP/Contents/MacOS/Owl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/install-helper.sh "$APP/Contents/Resources/"
xcrun swiftc Sources/OwlIcon.swift scripts/Icon.swift -o .build/icon
.build/icon "$PWD/.build"
iconutil -c icns .build/Owl.iconset -o "$APP/Contents/Resources/Owl.icns"
if [[ -f apple_secrets/owl-developer-id.cer && -f apple_secrets/owl-developer-id.key ]]; then
    python3 scripts/sign.py
else
    codesign --force --sign "${SIGNING_IDENTITY:--}" --options runtime "$APP/Contents/Resources/com.yonigo.Owl.helper"
    codesign --force --sign "${SIGNING_IDENTITY:--}" --options runtime "$APP"
fi
echo "Built $APP"
