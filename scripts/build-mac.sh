#!/usr/bin/env bash
# Builds the Mac menu bar app with SwiftPM (no Xcode project needed) and assembles
# build/Glasspad.app, ad-hoc signed. Works with Xcode or the command line tools; honours an
# existing DEVELOPER_DIR. Does not launch the app.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
# shellcheck source=scripts/toolchain.sh
source scripts/toolchain.sh

VERSION="${GLASSPAD_VERSION:-0.1.0}"
BUILD_NUMBER="${GLASSPAD_BUILD_NUMBER:-1}"
SCRATCH="$GP_BUILD_ROOT/GlasspadMac"
APP="$ROOT/build/Glasspad.app"
ASSETS="$ROOT/Apps/Mac/Resources/Assets.xcassets"

echo "== swift build (release)"
swift build -c release --package-path Apps/Mac --scratch-path "$SCRATCH" --product Glasspad \
  ${GP_SWIFT_FLAGS[@]+"${GP_SWIFT_FLAGS[@]}"}
BIN_DIR="$(swift build -c release --package-path Apps/Mac --scratch-path "$SCRATCH" --show-bin-path)"

echo "== assemble $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Glasspad" "$APP/Contents/MacOS/Glasspad"

# Now-playing helper: a small library /usr/bin/perl loads so Media mode can read MediaRemote,
# which since macOS 15.4 answers only Apple processes (see Apps/Mac/Helpers/NowPlayingHelper.m).
echo "== now-playing helper"
mkdir -p "$APP/Contents/Frameworks"
clang -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -fobjc-arc -dynamiclib -O2 \
  -Wall -Wextra -Wno-unused-parameter -Werror \
  -framework Foundation -framework AppKit \
  -install_name @rpath/GlasspadNowPlaying.dylib \
  -o "$APP/Contents/Frameworks/GlasspadNowPlaying.dylib" "$ROOT/Apps/Mac/Helpers/NowPlayingHelper.m"

# App icon: turn the asset catalog's PNGs into an .icns with iconutil.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for f in "$ASSETS"/AppIcon.appiconset/icon_*.png; do
  [ -e "$f" ] || continue
  name="$(basename "$f" | sed 's/@1x//')"
  cp "$f" "$ICONSET/$name"
done
if ls "$ICONSET"/*.png >/dev/null 2>&1; then
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi
# Menu bar template icon.
cp "$ASSETS"/MenuBarIcon.imageset/MenuBarIcon*.png "$APP/Contents/Resources/" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Glasspad</string>
  <key>CFBundleIdentifier</key><string>com.soham109.glasspad</string>
  <key>CFBundleName</key><string>Glasspad</string>
  <key>CFBundleDisplayName</key><string>Glasspad</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_glasspad._tcp</string>
  </array>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Glasspad listens on your local network so your paired iPhone can connect and work as a trackpad.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Glasspad shows what Spotify or Music is playing on your iPhone and controls playback, and opens Notification Center when you swipe in from the right edge.</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "== codesign (ad-hoc)"
# iCloud-synced folders tag bundles with Finder info; codesign refuses those attributes.
xattr -cr "$APP"
codesign --force --sign - --timestamp=none "$APP/Contents/Frameworks/GlasspadNowPlaying.dylib"
# The entitlements carry com.apple.security.automation.apple-events (Media mode's Apple Events).
codesign --force --sign - --timestamp=none --entitlements "$ROOT/Config/Mac/Glasspad.entitlements" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
