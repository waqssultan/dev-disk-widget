#!/bin/bash
# Builds DevDiskApp (menu bar app + Dev Disk Cleanup widget) locally and
# installs it into /Applications. No Apple ID / team signing required —
# uses ad-hoc "Sign to Run Locally" signing, which is why this MUST be run
# on each machine (a downloaded pre-built .app would get Gatekeeper-quarantined;
# a locally-built one never is).
#
# Usage:
#   git clone <this repo> DevDiskWidget && cd DevDiskWidget && ./install.sh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DevDiskApp"
INSTALL_PATH="/Applications/${APP_NAME}.app"
BUILD_DIR="$(pwd)/.build"

echo "==> Checking prerequisites"
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode command line tools not found. Install Xcode from the App Store first, then re-run this script." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found."
  if command -v brew >/dev/null 2>&1; then
    echo "Installing via Homebrew…"
    brew install xcodegen
  else
    echo "Install Homebrew (https://brew.sh) then run: brew install xcodegen" >&2
    exit 1
  fi
fi

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building (Release, ad-hoc signed, this machine's architecture only)"
xcodebuild \
  -project DevDiskWidget.xcodeproj \
  -scheme DevDiskApp \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  ONLY_ACTIVE_ARCH=YES \
  build

BUILT_APP="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "Build did not produce $BUILT_APP — check the log above." >&2
  exit 1
fi

echo "==> Installing to $INSTALL_PATH"
if pgrep -f "${INSTALL_PATH}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
  echo "Quitting the currently running copy…"
  pkill -f "${INSTALL_PATH}/Contents/MacOS/${APP_NAME}" || true
  sleep 1
fi
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP" "$INSTALL_PATH"

echo "==> Registering with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$INSTALL_PATH"

echo "==> Launching"
open "$INSTALL_PATH"

cat <<'EOF'

✅ Installed and running.

- Look for the internal-drive icon in your menu bar (top right).
- First scan takes ~10-20s (it's walking Gradle/DerivedData/etc).
- To add the Desktop widget: right-click Desktop → Edit Widgets →
  search "Dev Disk Cleanup" → drag it onto the Desktop.
- To make it start automatically at login: System Settings → General →
  Login Items → add DevDiskApp.

To reinstall after a code update, just re-run ./install.sh.
EOF
