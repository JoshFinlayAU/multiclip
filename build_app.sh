#!/bin/bash
#
# Builds MultiClip.app: compiles the SPM executable in release mode, assembles a
# proper .app bundle with Info.plist + icon + clipboard images, and ad-hoc signs
# it so the Keychain / Local Network / Accessibility prompts behave correctly.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/MultiClip.app"
CONFIG="${1:-release}"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/MultiClip"
if [[ ! -f "$BIN" ]]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/MultiClip"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Clipboard images used for the menu-bar icon (chosen at runtime by style).
cp "$ROOT/clipboard.png"        "$APP/Contents/Resources/clipboard.png"
cp "$ROOT/clipboard-black.png"  "$APP/Contents/Resources/clipboard-black.png"
cp "$ROOT/clipboard-color.png"  "$APP/Contents/Resources/clipboard-color.png"

echo "==> Generating app icon (.icns)…"
ICONSET="$(mktemp -d)/MultiClip.iconset"
mkdir -p "$ICONSET"
SRC="$ROOT/clipboard-color.png"
for size in 16 32 64 128 256 512; do
    sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/MultiClip.icns"

# Signing identity: ad-hoc ("-") by default; set SIGN_IDENTITY to a Developer ID
# for a distributable, notarizable build.
IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
    echo "==> Ad-hoc code signing…"
    codesign --force --sign - "$APP/Contents/MacOS/MultiClip"
    codesign --force --sign - "$APP"
else
    echo "==> Code signing with Developer ID + hardened runtime…"
    echo "    identity: $IDENTITY"
    # Sign inside-out: executable first, then the bundle.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/MultiClip"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
fi

echo "==> Done: $APP"
