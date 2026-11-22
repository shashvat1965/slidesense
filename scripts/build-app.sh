#!/bin/bash
#
# Builds SlideSense and assembles a proper .app bundle.
#
#   ./scripts/build-app.sh            # release build into ./SlideSense.app
#   ./scripts/build-app.sh --debug    # debug build
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
# Release builds are universal so the app also runs on Intel Macs; debug
# builds stay native to keep local iteration fast.
ARCH_FLAGS=(--arch arm64 --arch x86_64)
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="debug"
    ARCH_FLAGS=()
fi

VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo "0.1.0")"
APP_NAME="SlideSense"
APP="$ROOT/$APP_NAME.app"
BUNDLE_ID="io.github.slidesense"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --product SlideSense ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

BIN_PATH="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/SlideSense"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$APP_NAME"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT licensed.</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc, no identity)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
    echo "warning: ad-hoc codesigning failed; the app may still run" >&2
}

echo "==> Done: $APP"
echo "    Open it with: open \"$APP\""
echo "    Install with: make install"
