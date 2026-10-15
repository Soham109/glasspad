#!/bin/bash
# Records one scripted phone scene from the simulator for the film.
#   scripts/film/record-phone.sh <scene> <seconds> <orientation> [theme]
# Needs the Debug simulator build in ~/Library/Caches/glasspad-dd-film and the icon folder
# made by scripts/film/icons.swift in ~/Library/Caches/glasspad-film-icons.
set -euo pipefail
SCENE=$1; SECS=$2; ORIENT=${3:-portrait}; THEME=${4:-paper}
UDID=${GP_UDID:-$(xcrun simctl list devices available | grep "iPhone 18 Pro (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')}
APP=$HOME/Library/Caches/glasspad-dd-film/Build/Products/Debug-iphonesimulator/Glasspad.app
BID=com.soham109.glasspad.ios
OUT=$(cd "$(dirname "$0")/../.." && pwd)/public/v2/phone
mkdir -p "$OUT"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl ui "$UDID" appearance light
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" $BID 2>/dev/null || true
sleep 1
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/$SCENE.mov" > /dev/null 2>&1 &
REC=$!
sleep 1.5
xcrun simctl launch "$UDID" $BID -GPFilm "$SCENE" -GPDemo "$HOME/Library/Caches/glasspad-film-icons" \
  -GPOrientation "$ORIENT" -GPTheme "$THEME" > /dev/null
sleep "$SECS"
kill -INT $REC
wait $REC || true
echo "$OUT/$SCENE.mov"
