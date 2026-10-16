#!/bin/bash
# One still of the real app from the film's own simulator.
#   scripts/v4/shot.sh <out.png> <seconds to wait> [app launch args...]
# Env: GP_APP (path to Glasspad.app, default: this worktree's Debug build), GP_UDID (simulator),
# GP_ICONS (folder of Mac app icons made by scripts/film/icons.swift), GP_APPEARANCE (light|dark).
set -euo pipefail
OUT=$1; WAIT=$2; shift 2
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
UDID=${GP_UDID:?set GP_UDID to the film simulator}
APP=${GP_APP:-$ROOT/build/dd/Build/Products/Debug-iphonesimulator/Glasspad.app}
ICONS=${GP_ICONS:-$HOME/Library/Caches/glasspad-film-icons}
BID=com.soham109.glasspad.ios
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl ui "$UDID" appearance "${GP_APPEARANCE:-light}"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --operatorName "" > /dev/null 2>&1 || true
if [ "${GP_INSTALL:-1}" = 1 ]; then xcrun simctl install "$UDID" "$APP"; fi
xcrun simctl terminate "$UDID" $BID 2>/dev/null || true
xcrun simctl launch "$UDID" $BID -GPDemo "$ICONS" "$@" > /dev/null
sleep "$WAIT"
mkdir -p "$(dirname "$OUT")"
xcrun simctl io "$UDID" screenshot --type=png "$OUT" > /dev/null 2>&1
echo "$OUT"
