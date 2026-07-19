#!/usr/bin/env bash
set -euo pipefail

PROFILE_NAME="FuckWhispre-Notary"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Fuck Whispre notarization setup"
echo "Apple will ask for your Developer Apple ID, Team ID, and an app-specific password."
echo "The password is entered securely and saved in your macOS Keychain."
echo
read -r -p "Developer Apple ID (email): " APPLE_ID
echo "Team ID: 2LC96782A8"
xcrun notarytool store-credentials "$PROFILE_NAME" \
  --apple-id "$APPLE_ID" \
  --team-id "2LC96782A8"
echo
echo "Credentials saved. Building, submitting, and stapling the DMG…"
NOTARY_PROFILE="$PROFILE_NAME" "$ROOT_DIR/script/package_dmg.sh"
echo
echo "Notarization complete. The stapled DMG is in:"
echo "$ROOT_DIR/dist/Fuck Whispre.dmg"
read -r -p "Press Return to close this window."
