#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="${1:-}"

if [[ -z "$DMG" || ! -f "$DMG" ]]; then
  echo "usage: Scripts/notarize.sh build/Dockyard-<version>.dmg" >&2
  exit 1
fi

: "${NOTARY_KEY_ID:?set NOTARY_KEY_ID}"
: "${NOTARY_KEY_ISSUER:?set NOTARY_KEY_ISSUER}"
: "${NOTARY_KEY_PATH:?set NOTARY_KEY_PATH}"

echo "==> Submitting $DMG to the notary service"
xcrun notarytool submit "$DMG" \
  --key "$NOTARY_KEY_PATH" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_KEY_ISSUER" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"

echo "==> Verifying"
xcrun stapler validate "$DMG"
spctl -a -vvv -t open --context context:primary-signature "$DMG"
shasum -a 256 "$DMG"
