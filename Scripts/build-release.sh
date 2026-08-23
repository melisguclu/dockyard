#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Dockyard"
BUNDLE="$ROOT/build/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Dockyard/Info.plist")"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"

UNIVERSAL=1 "$ROOT/Scripts/make-app.sh" release

if [[ -n "$IDENTITY" ]]; then
  echo "==> Signing with Developer ID and Hardened Runtime"
  codesign --force --timestamp --options runtime \
    --entitlements "$ROOT/Dockyard/Dockyard.entitlements" \
    --sign "$IDENTITY" "$BUNDLE"
else
  echo "==> No DEVELOPER_ID_APPLICATION set, signing ad hoc (not distributable)"
  codesign --force --entitlements "$ROOT/Dockyard/Dockyard.entitlements" --sign - "$BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$BUNDLE"
codesign -d --entitlements :- "$BUNDLE"

echo "==> Building disk image"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGE"

echo "==> Artifact: $DMG"
shasum -a 256 "$DMG"
