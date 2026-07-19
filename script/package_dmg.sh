#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Fuck Whispre"
DEFAULT_IDENTITY="91979A25F16143B38EEAD518501C7EAC113F4D52"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
RW_DMG="$ROOT_DIR/dist/$APP_NAME-rw.dmg"

"$ROOT_DIR/script/build_app.sh" release

STAGING_DIR="$(mktemp -d /private/tmp/fuck-whispre-dmg.XXXXXX)"
MOUNT_DIR=""
cleanup() {
  if [[ -n "$MOUNT_DIR" ]]; then hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true; fi
  rm -rf "$STAGING_DIR"
  rm -f "$RW_DMG"
}
trap cleanup EXIT
cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
xattr -cr "$STAGING_DIR/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir -p "$STAGING_DIR/.background"
swift "$ROOT_DIR/script/make_dmg_background.swift" \
  "$STAGING_DIR/.background/background.png"

rm -f "$DMG_PATH" "$RW_DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -ov \
  -format UDRW \
  "$RW_DMG"

ATTACH_OUTPUT="$(hdiutil attach -readwrite -nobrowse "$RW_DMG")"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// {sub(/^.*\t/, ""); print; exit}')"
if [[ -z "$MOUNT_DIR" ]]; then
  echo "Could not determine the mounted DMG path." >&2
  exit 1
fi
sleep 1
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set bounds of container window to {120, 120, 800, 508}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 112
    set text size of theViewOptions to 12
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {180, 170}
    set position of item "Applications" of container window to {500, 170}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach "$MOUNT_DIR" >/dev/null

hdiutil convert "$RW_DMG" -format UDZO -ov -o "$DMG_PATH" >/dev/null

SIGN_IDENTITY="${SIGN_IDENTITY:-$DEFAULT_IDENTITY}"
if security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

codesign --verify --verbose=2 "$DMG_PATH"
hdiutil imageinfo "$DMG_PATH" >/dev/null

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo "$DMG_PATH"
