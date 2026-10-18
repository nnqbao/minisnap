#!/usr/bin/env bash
# Builds MiniSnap.app (universal when possible), ad-hoc signs it and zips it.
# Output: macos/dist/MiniSnap.app and macos/dist/MiniSnap-macOS.zip
set -euo pipefail

cd "$(dirname "$0")"

DIST="dist"
APP="$DIST/MiniSnap.app"

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Swift toolchain"
swift --version || true

echo "==> Building (universal: arm64 + x86_64)"
if swift build -c release --arch arm64 --arch x86_64; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
    echo "Universal build failed; falling back to the native architecture." >&2
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
fi
BIN="$BIN_DIR/MiniSnap"
if [ ! -f "$BIN" ]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi
lipo -info "$BIN" || true

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MiniSnap"
chmod +x "$APP/Contents/MacOS/MiniSnap"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> App icon (optional)"
if swift Scripts/make_icon.swift "$DIST/AppIcon.iconset" \
    && iconutil -c icns "$DIST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"; then
    echo "AppIcon.icns created"
else
    echo "warning: app icon could not be generated; continuing without it" >&2
fi
rm -rf "$DIST/AppIcon.iconset"

# With a fixed certificate (CI imports it from the repository secrets) the signature, and so the identity
# macOS remembers the Screen Recording permission by, stays the same across versions. An ad-hoc signature
# changes with every build, so macOS asks for the permission again after each update.
if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
    echo "==> Code signing with \"$MACOS_SIGN_IDENTITY\""
    codesign --force --deep --timestamp=none --sign "$MACOS_SIGN_IDENTITY" ${MACOS_KEYCHAIN:+--keychain "$MACOS_KEYCHAIN"} "$APP"
else
    echo "==> Ad-hoc code signing (no certificate: Screen Recording permission resets with each build)"
    codesign --force --deep --sign - "$APP"
fi
codesign --verify --verbose=2 "$APP" || true
codesign --display --requirements - "$APP" 2>&1 | tail -n 1 || true

echo "==> Zipping"
ditto -c -k --keepParent "$APP" "$DIST/MiniSnap-macOS.zip"

echo "Done:"
ls -la "$DIST"
