#!/bin/bash
# Re-captures every phone screen in the v4 film from the real app, in the simulator.
#
#   scripts/v4/capture.sh                 build the app(s) and capture every shot
#   scripts/v4/capture.sh actions remote  capture only the shots whose names start with these
#
# Each shot comes from an app build of a git ref. Until every feature is merged, some shots
# come from feature branches (APP_<NAME> below); once they are in integrate, point them all at
# integrate (or run with GP_ALL_REF=integrate). Builds are made from `git archive` snapshots,
# so no other worktree is touched. If a snapshot predates the film's demo scenes
# (Apps/iOS/Sources/App/FilmV4.swift), the scenes are copied in from feat/film.
#
# Env: GP_UDID (the film's simulator, required), GP_REPO (default ~/Projects/glasspad),
# GP_ICONS (Mac app icons from scripts/film/icons.swift), GP_ALL_REF (one ref for every shot).
# Output: public/v4/phone/<shot>.png or .mp4 (60 fps, constant frame rate), plus shots.json.
set -euo pipefail
cd "$(dirname "$0")/../.."
PROMO=$(pwd)
UDID=${GP_UDID:?set GP_UDID to the film simulator}
REPO=${GP_REPO:-$HOME/Projects/glasspad}
CACHE=${GP_CACHE:-$HOME/Library/Caches/glasspad-film-capture}
ICONS=${GP_ICONS:-$HOME/Library/Caches/glasspad-film-icons}
OUT=$PROMO/public/v4/phone
BID=com.soham109.glasspad.ios
mkdir -p "$OUT" "$CACHE"

# Which ref each feature's shots are built from.
APP_BASE=${GP_ALL_REF:-integrate}
APP_LAYOUTS=${GP_ALL_REF:-integrate} # Layouts, Displays and StandBy are in integrate now
FILM_REF=${GP_FILM_REF:-feat/film}

# name | app | still or video seconds (v<seconds>) | wait before a still | launch arguments
SHOTS=$(cat <<'EOF'
actions-switch|BASE|v10|0|-GPFilm v4-actions -GPOrientation landscape -GPTheme graphite
pinned|BASE|s|3|-GPFilm v4-pinned -GPOrientation landscape -GPTheme graphite
pinned-paper|BASE|s|3|-GPFilm v4-pinned -GPOrientation landscape -GPTheme paper
pinned-mono|BASE|s|3|-GPFilm v4-pinned -GPOrientation landscape -GPTheme mono
actions-mail|BASE|s|3.5|-GPFilm v4-actions -GPOrientation portrait -GPTheme paper
actions-portrait|BASE|s|3|-GPFilm v4-pinned -GPOrientation portrait -GPTheme paper
finalcut|BASE|s|3|-GPFilm v4-finalcut -GPOrientation portrait -GPTheme graphite
present|BASE|s|4|-GPMode actions -GPFilm v4-layout -GPActionsPage present -GPOrientation portrait -GPTheme graphite
remote|BASE|s|4|-GPMode actions -GPFilm v4-layout -GPActionsPage remote -GPMediaDemo movie -GPOrientation portrait -GPTheme graphite
remote-search|BASE|s|4|-GPMode actions -GPFilm v4-layout -GPActionsPage remote -GPMediaDemo movie -GPRemoteSearch -GPOrientation portrait -GPTheme graphite
clipboard|BASE|s|4|-GPMode actions -GPFilm v4-layout -GPActionsPage clipboard -GPOrientation portrait -GPTheme paper
clipboard-text|BASE|s|4|-GPMode actions -GPFilm v4-layout -GPActionsPage clipboard -GPOrientation portrait -GPTheme paper
menu|BASE|v9|0|-GPMode trackpad -GPFilm menu -GPOrientation portrait -GPTheme graphite
keys|BASE|s|4|-GPMode keys -GPOrientation landscape -GPTheme graphite
media|BASE|s|4|-GPMode media -GPFilm media -GPOrientation portrait -GPTheme graphite
dock|BASE|s|4|-GPMode dock -GPOrientation portrait -GPTheme graphite
macros|BASE|s|4|-GPMode actions -GPFilm v4-layout -GPActionsPage library -GPOrientation portrait -GPTheme graphite
trackpad|BASE|v14|0|-GPMode trackpad -GPFilm trackpad -GPOrientation landscape -GPTheme graphite
layout|LAYOUTS|s|4|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPOrientation landscape -GPTheme graphite
layout-drag|LAYOUTS|s|4|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.62 -GPOrientation landscape -GPTheme graphite
layout-drag-097|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.97 -GPOrientation landscape -GPTheme graphite
layout-drag-093|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.93 -GPOrientation landscape -GPTheme graphite
layout-drag-089|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.89 -GPOrientation landscape -GPTheme graphite
layout-drag-085|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.85 -GPOrientation landscape -GPTheme graphite
layout-drag-081|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.81 -GPOrientation landscape -GPTheme graphite
layout-drag-077|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.77 -GPOrientation landscape -GPTheme graphite
layout-drag-073|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.73 -GPOrientation landscape -GPTheme graphite
layout-drag-069|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.69 -GPOrientation landscape -GPTheme graphite
layout-drag-065|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.65 -GPOrientation landscape -GPTheme graphite
layout-drag-061|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.61 -GPOrientation landscape -GPTheme graphite
layout-drag-057|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.57 -GPOrientation landscape -GPTheme graphite
layout-drag-053|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.53 -GPOrientation landscape -GPTheme graphite
layout-drag-050|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.5 -GPLayoutDragDemo 0.5 -GPOrientation landscape -GPTheme graphite
layout-fold|LAYOUTS|s|4|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 1.0 -GPOrientation landscape -GPTheme graphite
layout-clock|LAYOUTS|s|4|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-004|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.04 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-008|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.08 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-012|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.12 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-016|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.16 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-020|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.2 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-024|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.24 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-028|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.28 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-032|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.32 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-036|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.36 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-040|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.4 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-044|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.44 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-047|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.47 -GPOrientation landscape -GPTheme graphite
layout-clock-drag-050|LAYOUTS|s|3.5|-GPFilm v4-layout -GPLayoutPanes clock,actions -GPStandByTime 10:30 -GPLayoutDragDemo 0.5 -GPOrientation landscape -GPTheme graphite
displays|BASE|s|4|-GPMode actions -GPFilm v4-layout -GPActionsPage displays -GPDisplaysDemo two -GPOrientation portrait -GPTheme graphite
displays-l|BASE|s|4|-GPMode actions -GPFilm v4-layout -GPActionsPage displays -GPDisplaysDemo two -GPOrientation landscape -GPTheme graphite
displays-move|BASE|v9|0|-GPMode actions -GPFilm v4-displays -GPActionsPage displays -GPDisplaysDemo two -GPOrientation portrait -GPTheme graphite
displays-arrange|BASE|s|4|-GPMode actions -GPFilm v4-layout -GPActionsPage displays -GPDisplaysDemo two -GPDisplaysArrange -GPOrientation portrait -GPTheme graphite
standby|BASE|s|4|-GPFilm v4-layout -GPLayout standby -GPStandByTime 10:30 -GPOrientation landscape -GPTheme graphite
layout-after|LAYOUTS|s|4|-GPFilm v4-layout -GPLayout media-actions -GPLayoutSplit 0.62 -GPOrientation landscape -GPTheme graphite
EOF
)

# Build the app from a ref into $CACHE/<slug>; prints the .app path.
build() {
  local ref=$1 slug=${1//\//-}
  local src=$CACHE/src-$slug dd=$CACHE/dd-$slug
  # The cache key covers the ref and the film's demo scenes that may be copied into it.
  local sha; sha="$(git -C "$REPO" rev-parse "$ref") $(git -C "$REPO" rev-parse "$FILM_REF:Apps/iOS/Sources/App/FilmV4.swift")"
  if [ -f "$CACHE/$slug.sha" ] && [ "$(cat "$CACHE/$slug.sha")" = "$sha" ] && [ -d "$dd/Build/Products/Debug-iphonesimulator/Glasspad.app" ]; then
    echo "$dd/Build/Products/Debug-iphonesimulator/Glasspad.app"; return
  fi
  rm -rf "$src"; mkdir -p "$src"
  git -C "$REPO" archive "$ref" | tar -x -C "$src"
  if [ ! -f "$src/Apps/iOS/Sources/App/FilmV4.swift" ]; then
    git -C "$REPO" show "$FILM_REF:Apps/iOS/Sources/App/FilmV4.swift" > "$src/Apps/iOS/Sources/App/FilmV4.swift"
    python3 -I - "$src/Apps/iOS/Sources/App/DemoScript.swift" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "        self.iconFolder = iconFolder\n"
hook = "        if FilmV4.start(scene: scene, iconFolder: iconFolder) { return }\n"
if hook not in s:
    s = s.replace(anchor, anchor + hook, 1)
open(p, "w").write(s)
PY
  fi
  (cd "$src" && xcodegen -q && xcodebuild -project Glasspad.xcodeproj -scheme "Glasspad iOS" -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$dd" -jobs 4 build > "$CACHE/build-$slug.log" 2>&1) \
    || { echo "build of $ref failed, see $CACHE/build-$slug.log" >&2; exit 1; }
  echo "$sha" > "$CACHE/$slug.sha"
  echo "$dd/Build/Products/Debug-iphonesimulator/Glasspad.app"
}

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 > /dev/null 2>&1 || true

installed=""
# The shot list is read on its own descriptor, so nothing in the loop can swallow it.
while IFS='|' read -r name app kind wait args <&3; do
  [ -z "$name" ] && continue
  if [ $# -gt 0 ]; then
    keep=0; for p in "$@"; do case $name in "$p"*) keep=1;; esac; done
    [ $keep = 1 ] || continue
  fi
  ref_var=APP_$app; ref=${!ref_var}
  appdir=$(build "$ref")
  if [ "$installed" != "$appdir" ]; then
    xcrun simctl uninstall "$UDID" $BID 2>/dev/null || true
    xcrun simctl install "$UDID" "$appdir" < /dev/null; installed=$appdir
  fi
  xcrun simctl terminate "$UDID" $BID 2>/dev/null < /dev/null || true
  # The Clipboard shot needs something copied on the phone first.
  case $name in clipboard-text) printf "%s" "Bring the prints for Mira, and the projector cable." | xcrun simctl pbcopy "$UDID";; clipboard) printf "" | xcrun simctl pbcopy "$UDID";; esac
  # shellcheck disable=SC2086
  if [ "${kind:0:1}" = v ]; then
    secs=${kind:1}
    rm -f "$CACHE/$name.mov"
    xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$CACHE/$name.mov" > /dev/null 2>&1 &
    rec=$!
    trap 'kill -INT $rec 2>/dev/null || true' EXIT
    sleep 1.5
    xcrun simctl launch "$UDID" $BID -GPDemo "$ICONS" $args > /dev/null < /dev/null
    sleep "$secs"
    kill -INT $rec 2>/dev/null || echo "recording of $name stopped early" >&2; wait $rec || true
    # Constant 60 fps (the simulator writes frames only when the screen changes, so the last
    # still moment is held for a few seconds), short GOPs for exact seeking in Remotion.
    # The simulator records in the device's portrait frame; sideways shots are turned upright.
    rot=""; case "$args" in *"-GPOrientation landscape"*) rot=",transpose=2";; esac
    ffmpeg -nostdin -v error -y -i "$CACHE/$name.mov" -vf "fps=60$rot,tpad=stop_mode=clone:stop_duration=4" -c:v libx264 -preset slow -crf 12 -g 30 -pix_fmt yuv420p "$OUT/$name.mp4"
    echo "$name.mp4 ($ref)"
  else
    xcrun simctl launch "$UDID" $BID -GPDemo "$ICONS" $args > /dev/null < /dev/null
    sleep "$wait"
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" > /dev/null 2>&1 < /dev/null
    echo "$name.png ($ref)"
  fi
done 3<<< "$SHOTS"

# A record of where each shot came from.
python3 -I - "$OUT" <<'PY'
import json, os, subprocess, sys
out = sys.argv[1]
items = {}
for f in sorted(os.listdir(out)):
    p = os.path.join(out, f)
    if f.endswith(".png"):
        from struct import unpack
        with open(p, "rb") as fh:
            fh.read(16); w, h = unpack(">II", fh.read(8))
        items[f] = dict(w=w, h=h)
    elif f.endswith(".mp4"):
        r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=width,height,nb_frames",
                            "-of", "json", p], capture_output=True, text=True).stdout
        s = json.loads(r)["streams"][0]
        items[f] = dict(w=s["width"], h=s["height"], frames=int(s.get("nb_frames", 0)))
json.dump(items, open(os.path.join(out, "shots.json"), "w"), indent=1)
PY
echo "done: $OUT"
