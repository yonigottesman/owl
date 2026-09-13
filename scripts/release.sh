#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${NOTARY_PROFILE:-Owl-notarization}"
KEYCHAIN="${NOTARY_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
./build.sh
mkdir -p dist
ditto -c -k --keepParent Owl.app dist/Owl-notarization.zip
xcrun notarytool submit dist/Owl-notarization.zip --keychain-profile "$PROFILE" --keychain "$KEYCHAIN" --wait
xcrun stapler staple Owl.app
xcrun stapler validate Owl.app
spctl --assess --type execute --verbose=2 Owl.app
STAGING="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto Owl.app "$STAGING/Owl.app"
ln -s /Applications "$STAGING/Applications"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Owl.app/Contents/Info.plist)"
DMG="dist/Owl-$VERSION-$(uname -m).dmg"
hdiutil create -volname Owl -srcfolder "$STAGING" -ov -format UDZO "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --keychain "$KEYCHAIN" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Ready to share: $DMG"
