#!/bin/bash
#
# Produces a fully signed, notarized, stapled MultiClip.dmg ready for
# distribution. Requires:
#   * a "Developer ID Application" identity in the login keychain
#   * a notarytool keychain profile (default name: multiclip-notary), created via:
#       xcrun notarytool store-credentials multiclip-notary \
#         --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Serenity Space Pty Ltd (4S7BG5A4XV)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-multiclip-notary}"

APP="$ROOT/build/MultiClip.app"
DIST="$ROOT/dist"
STAGING="$ROOT/build/dmg-staging"

# --- 1. Build + Developer ID sign -------------------------------------------
SIGN_IDENTITY="$IDENTITY" "$ROOT/build_app.sh" release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/MultiClip-$VERSION.dmg"
mkdir -p "$DIST"

# --- 2. Notarize the app, then staple it ------------------------------------
echo "==> Submitting app for notarization…"
APP_ZIP="$ROOT/build/MultiClip-app.zip"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
echo "==> Stapling app…"
xcrun stapler staple "$APP"

# --- 3. Build the DMG from the stapled app ----------------------------------
echo "==> Building DMG…"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "MultiClip" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

# --- 4. Notarize the DMG, then staple it ------------------------------------
echo "==> Submitting DMG for notarization…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
echo "==> Stapling DMG…"
xcrun stapler staple "$DMG"

# --- 5. Verify --------------------------------------------------------------
echo "==> Verifying Gatekeeper assessment…"
spctl -a -vvv "$APP" || true
xcrun stapler validate "$DMG"

echo
echo "==> Release ready: $DMG"
