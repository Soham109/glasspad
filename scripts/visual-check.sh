#!/usr/bin/env bash
# Visual regression check for the iPhone app, in the simulator only.
#
# Builds the app (Debug, for the demo launch arguments), then for every screen in
# scripts/visual-screens.txt and each theme (Paper, Graphite, Mono, Blue tinted in dark, Grain;
# `name:dark` turns the phone dark for that theme) starts it fresh, launches it
# with that screen's arguments and sample Mac data, and takes a screenshot. Then compares them
# with a baseline (scripts/visual-diff.py) and lists every screen that changed, with side by
# side pictures.
#
#   scripts/visual-check.sh --baseline DIR [--record] [--out DIR] [--sim NAME] [--app PATH]
#                           [--icons DIR] [--only REGEX] [--themes "paper graphite mono monoBlue:dark grain"]
#
#   --record      take the screens into the baseline folder instead of comparing
#   --app PATH    use a built Glasspad.app instead of building
#   --icons DIR   folder of sample app icons with a list.json (GLASSPAD_DEMO_ICONS); optional
#   --only REGEX  only screens whose name matches
#   --sim NAME    simulator to use (default GP-guard); it is booted and shut down again
#   --resume      keep the screens already taken in this folder and take only the missing ones
# GLASSPAD_MAX_LOAD=<n>: before each launch, wait while the Mac's 5 minute load average is over n
#
# Exit 0 when nothing changed beyond its allowance, 1 when something did, 2 on a setup error.
# Never touches a real iPhone or this Mac's screen.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

RESUME=0; SIM="GP-guard"; BASELINE="${GLASSPAD_VISUAL_BASELINE:-}"; OUT="$ROOT/build/visual/now"; APP=""; RECORD=0
ICONS="${GLASSPAD_DEMO_ICONS:-}"; ONLY=""; THEMES="paper graphite mono monoBlue:dark grain"; WAIT="${GLASSPAD_VISUAL_WAIT:-3}"
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) BASELINE="$2"; shift 2 ;;
    --record) RECORD=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    --sim) SIM="$2"; shift 2 ;;
    --app) APP="$2"; shift 2 ;;
    --icons) ICONS="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --themes) THEMES="$2"; shift 2 ;;
    --resume) RESUME=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$BASELINE" ] || { echo "--baseline DIR is needed" >&2; exit 2; }
BID=com.soham109.glasspad.ios
UDID="$(xcrun simctl list devices available | sed -n "s/^ *$SIM (\([0-9A-F-]*\)).*/\1/p" | head -1)"
[ -n "$UDID" ] || { echo "no simulator named $SIM (xcrun simctl create $SIM \"iPhone 17 Pro\")" >&2; exit 2; }

if [ -z "$APP" ]; then
  echo "== build"
  command -v xcodegen >/dev/null && xcodegen generate >/dev/null
  xcodebuild -project Glasspad.xcodeproj -scheme "Glasspad iOS" -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath build/dd -jobs 4 build >"$ROOT/build/visual-build.log" 2>&1 \
    || { tail -30 "$ROOT/build/visual-build.log"; echo "build failed" >&2; exit 2; }
  APP="$ROOT/build/dd/Build/Products/Debug-iphonesimulator/Glasspad.app"
fi
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 2; }

SHOTS="$OUT/shots"
[ "$RECORD" = 1 ] && SHOTS="$BASELINE"
[ "$RESUME" = 1 ] || rm -rf "$SHOTS"
mkdir -p "$SHOTS" "$OUT"
calm() {
  [ -n "${GLASSPAD_MAX_LOAD:-}" ] || return 0
  while [ "$(sysctl -n vm.loadavg | awk '{print int($2)}')" -gt "$GLASSPAD_MAX_LOAD" ]; do sleep 30; done
}

echo "== simulator $SIM ($UDID)"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl ui "$UDID" appearance light
current_look=light
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true' EXIT

# A clean install once, then before each screen the app's saved data is removed and the
# simulator's preferences daemon restarted (it keeps a copy in memory), so no screen sees
# what an earlier one saved. Faster than reinstalling every time.
xcrun simctl uninstall "$UDID" "$BID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"
fresh_start() {
  xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
  local data
  data="$(xcrun simctl get_app_container "$UDID" "$BID" data)"
  rm -rf "$data/Library/Preferences" "$data/Library/Application Support" "$data/Library/Saved Application State" \
    "$data/Library/Caches" "$data/Documents" "$data/tmp"
  mkdir -p "$data/Library/Preferences" "$data/Documents" "$data/tmp"
  xcrun simctl spawn "$UDID" launchctl kill SIGKILL system/com.apple.cfprefsd.xpc.daemon >/dev/null 2>&1 || true
}

DEMO=(); [ -n "$ICONS" ] && DEMO=(-GPDemo "$ICONS")
[ -z "$ICONS" ] && DEMO=(-GPDemo "$ROOT/build/no-icons")
ALLOW=()
count=0
while IFS='|' read -r name allow args; do
  name="$(echo "$name" | xargs)"; allow="$(echo "$allow" | xargs)"
  case "$name" in ''|'#'*) continue ;; esac
  [ -n "$ONLY" ] && ! [[ "$name" =~ $ONLY ]] && continue
  [ -n "$allow" ] && ALLOW+=(--allow "$name=$allow")
  for spec in $THEMES; do
    theme="${spec%%:*}"; look=light
    [ "$spec" != "$theme" ] && look="${spec#*:}"
    file="$SHOTS/$name@${spec/:/-}.png"
    [ "$RESUME" = 1 ] && [ -s "$file" ] && continue
    calm
    if [ "$look" != "$current_look" ]; then xcrun simctl ui "$UDID" appearance "$look"; current_look=$look; fi
    fresh_start
    # shellcheck disable=SC2086
    xcrun simctl launch "$UDID" "$BID" "${DEMO[@]}" -GPTheme "$theme" -GPStandByTime 9:41 $args >/dev/null
    sleep "$WAIT"
    # Keep taking it until two in a row match (launch finished, animations settled), at most 6 s more.
    xcrun simctl io "$UDID" screenshot "$file" >/dev/null 2>&1 || echo "could not take $name@$theme" >&2
    for _ in 1 2 3 4 5 6; do
      sleep 1
      xcrun simctl io "$UDID" screenshot "$OUT/settle.png" >/dev/null 2>&1 || break
      if python3 -I "$ROOT/scripts/visual-diff.py" --same "$file" "$OUT/settle.png"; then break; fi
      mv "$OUT/settle.png" "$file"
    done
    rm -f "$OUT/settle.png"
    count=$((count + 1))
  done
done < "$ROOT/scripts/visual-screens.txt"
xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
echo "== $count screens in $SHOTS"

if [ "$RECORD" = 1 ]; then
  echo "baseline recorded in $BASELINE"
  exit 0
fi
FILTER=(); [ -n "$ONLY" ] && FILTER=(--current-only)
python3 -I "$ROOT/scripts/visual-diff.py" "$BASELINE" "$SHOTS" "$OUT" ${ALLOW[@]+"${ALLOW[@]}"} ${FILTER[@]+"${FILTER[@]}"}
