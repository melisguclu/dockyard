#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-debug}"
UNIVERSAL="${UNIVERSAL:-0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Dockyard"
BUNDLE="$ROOT/build/$APP_NAME.app"

cd "$ROOT"

BUILD_ARGS=(--configuration "$CONFIGURATION")
if [[ "$UNIVERSAL" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "==> Building $APP_NAME ($CONFIGURATION, universal=$UNIVERSAL)"
swift build "${BUILD_ARGS[@]}"

BINARY="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$APP_NAME"
if [[ ! -f "$BINARY" ]]; then
  echo "!! Built binary not found at $BINARY" >&2
  exit 1
fi

echo "==> Assembling bundle at $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Dockyard/Info.plist" "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

if [[ -f "$ROOT/Dockyard/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Dockyard/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

for BUNDLE_PATH in "$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"/*.bundle; do
  [[ -e "$BUNDLE_PATH" ]] || continue
  cp -R "$BUNDLE_PATH" "$BUNDLE/Contents/Resources/"
done

plutil -lint "$BUNDLE/Contents/Info.plist" > /dev/null

IDENTITY="${DOCKYARD_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ { print $2; exit }')"
fi

if [[ -n "$IDENTITY" ]]; then
  echo "==> Signing as $IDENTITY"
  codesign --force --options runtime \
    --identifier "com.dockyard.app" \
    --entitlements "$ROOT/Dockyard/Dockyard.entitlements" \
    --sign "$IDENTITY" "$BUNDLE"
else
  echo "==> No signing identity found, leaving the ad-hoc signature in place"
  echo "    TCC grants such as Accessibility will not survive a rebuild"
fi

echo "==> Built $BUNDLE"
