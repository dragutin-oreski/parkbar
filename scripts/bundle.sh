#!/bin/zsh
# Builds ParkBar, wraps it in a minimal .app (so it lives in the menu bar only) with the widget and the
# example notes inside, and signs it.
#
#   scripts/bundle.sh [debug|release]
#
# Signing is ad-hoc by default: fine for the app on this Mac. To sign with a stable identity instead (it
# helps the widget; see scripts/make-signing-identity.sh), set PARKBAR_SIGN_IDENTITY to its name.
# INSTALL_TO=/Applications also copies the app there and registers the widget.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
IDENTITY="${PARKBAR_SIGN_IDENTITY:--}"
APP_ID="dev.parkbar.ParkBar"
WIDGET_ID="dev.parkbar.ParkBar.Widget"

swift build -c "$CONFIG" --product ParkBar
swift build -c "$CONFIG" --product parkbar-cli
swift build -c "$CONFIG" --product ParkBarWidget

BIN=".build/$CONFIG"
APP="build/ParkBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ParkBar" "$APP/Contents/MacOS/ParkBar"
cp Sources/ParkBar/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# "Try the example notes" finds these from anywhere the app is copied to.
cp -R examples "$APP/Contents/Resources/examples"

# WidgetKit extension, embedded as an .appex (sandboxed; entitlements in Packaging/).
APPEX="$APP/Contents/PlugIns/ParkBarWidget.appex"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
cp "$BIN/ParkBarWidget" "$APPEX/Contents/MacOS/ParkBarWidget"
cp Packaging/ParkBarWidget-Info.plist "$APPEX/Contents/Info.plist"
printf 'XPC!????' > "$APPEX/Contents/PkgInfo"

sign() { # identity target identifier [entitlements]
  local args=(--force --sign "$1" --identifier "$3" --timestamp=none)
  [ -n "${4:-}" ] && args+=(--entitlements "$4")
  codesign "${args[@]}" "$2"
}

if [ "$IDENTITY" != "-" ] && ! security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  echo "WARNING: signing identity '$IDENTITY' not found; signing ad-hoc instead." >&2
  IDENTITY="-"
fi
sign "$IDENTITY" "$APPEX" "$WIDGET_ID" Packaging/ParkBarWidget.entitlements
sign "$IDENTITY" "$APP" "$APP_ID"
echo "signed with '$IDENTITY'$([ "$IDENTITY" = "-" ] && echo ' (ad-hoc)')"
codesign --verify --deep --strict "$APP" && echo "signature verified"

# Optional: install (copy + re-sign in place, since copying can disturb the seal) and register the widget.
if [ -n "${INSTALL_TO:-}" ]; then
  rm -rf "$INSTALL_TO/ParkBar.app"
  cp -R "$APP" "$INSTALL_TO/ParkBar.app"
  sign "$IDENTITY" "$INSTALL_TO/ParkBar.app/Contents/PlugIns/ParkBarWidget.appex" "$WIDGET_ID" Packaging/ParkBarWidget.entitlements
  sign "$IDENTITY" "$INSTALL_TO/ParkBar.app" "$APP_ID"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_TO/ParkBar.app" >/dev/null 2>&1 || true
  pluginkit -a "$INSTALL_TO/ParkBar.app/Contents/PlugIns/ParkBarWidget.appex" 2>/dev/null || true
  echo "installed to $INSTALL_TO/ParkBar.app"
fi
echo "app: $APP   cli: $BIN/parkbar-cli"
