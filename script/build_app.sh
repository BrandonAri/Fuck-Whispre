#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

APP_NAME="Fuck Whispre"
EXECUTABLE_NAME="FuckWisprFlow"
BUNDLE_ID="com.brandon.FuckWisprFlow"
MIN_SYSTEM_VERSION="14.0"
VERSION="1.0.1"
BUILD_NUMBER="2"
DEFAULT_IDENTITY="91979A25F16143B38EEAD518501C7EAC113F4D52"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DEST_APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
WORK_DIR="$(mktemp -d /private/tmp/fuck-wispr-flow-app.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
APP_BUNDLE="$WORK_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
WHISPER_BINARY="$ROOT_DIR/Vendor/whisper.cpp/build-static/bin/whisper-cli"
WHISPER_SERVER="$ROOT_DIR/Vendor/whisper.cpp/build-static/bin/whisper-server"
WHISPER_MODEL="$ROOT_DIR/Runtime/Models/ggml-base.en.bin"
ICON_FILE="$ROOT_DIR/Assets/AppIcon.icns"
ENTITLEMENTS="$ROOT_DIR/Config/Entitlements.plist"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"
BUILD_BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/$EXECUTABLE_NAME"

for required in "$BUILD_BINARY" "$WHISPER_BINARY" "$WHISPER_SERVER" "$WHISPER_MODEL" "$ICON_FILE" "$ENTITLEMENTS"; do
  if [[ ! -e "$required" ]]; then
    echo "Missing required build input: $required" >&2
    exit 1
  fi
done

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$WHISPER_BINARY" "$APP_RESOURCES/whisper-cli"
cp "$WHISPER_SERVER" "$APP_RESOURCES/whisper-server"
cp "$WHISPER_MODEL" "$APP_RESOURCES/ggml-base.en.bin"
cp "$ROOT_DIR/Vendor/whisper.cpp/LICENSE" "$APP_RESOURCES/whisper.cpp-LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
cp "$ICON_FILE" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY" "$APP_RESOURCES/whisper-cli" "$APP_RESOURCES/whisper-server"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$EXECUTABLE_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
<key>LSUIElement</key><true/>
<key>LSMultipleInstancesProhibited</key><true/>
<key>NSHumanReadableCopyright</key><string>Built for local, private dictation.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSMicrophoneUsageDescription</key><string>Fuck Whispre records only when you invoke Fn dictation so it can transcribe locally on your Mac.</string>
</dict></plist>
PLIST

xattr -cr "$APP_BUNDLE"

SIGN_IDENTITY="${SIGN_IDENTITY:-$DEFAULT_IDENTITY}"
if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
  SIGN_IDENTITY="-"
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --options runtime --timestamp=none --sign - "$APP_RESOURCES/whisper-cli"
  codesign --force --options runtime --timestamp=none --sign - "$APP_RESOURCES/whisper-server"
  xattr -cr "$APP_BUNDLE"
  codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign - "$APP_BUNDLE"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_RESOURCES/whisper-cli"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_RESOURCES/whisper-server"
  xattr -cr "$APP_BUNDLE"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
rm -rf "$DEST_APP_BUNDLE"
/usr/bin/ditto "$APP_BUNDLE" "$DEST_APP_BUNDLE"
xattr -cr "$DEST_APP_BUNDLE"
echo "$DEST_APP_BUNDLE"
