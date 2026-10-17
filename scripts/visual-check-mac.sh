#!/usr/bin/env bash
# Visual regression check for the Mac app's windows (popover, welcome, Settings panes, Live
# Check), in light and dark. Draws them off screen with the snapshot harness in
# Apps/Mac/Tests (no window is shown, nothing is clicked) and compares them with a baseline.
#
#   scripts/visual-check-mac.sh --baseline DIR [--record] [--out DIR]
#
# Exit 0 when nothing changed beyond its allowance (0.3% of its pixels unless named below), 1 when something did, 2 on an error.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
# shellcheck source=scripts/toolchain.sh
source scripts/toolchain.sh

BASELINE=""; OUT="$ROOT/build/visual-mac/now"; RECORD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) BASELINE="$2"; shift 2 ;;
    --record) RECORD=1; shift ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$BASELINE" ] || { echo "--baseline DIR is needed" >&2; exit 2; }
SHOTS="$OUT/shots"
[ "$RECORD" = 1 ] && SHOTS="$BASELINE"
rm -rf "$SHOTS"; mkdir -p "$SHOTS" "$OUT"

echo "== Mac snapshots"
GLASSPAD_SNAPSHOTS=1 GLASSPAD_SNAPSHOT_DIR="$SHOTS" swift test --package-path Apps/Mac \
  --scratch-path "$GP_BUILD_ROOT/GlasspadMacDebug" --filter 'SnapshotTests|LiveCheckSnapshots' \
  ${GP_SWIFT_FLAGS[@]+"${GP_SWIFT_FLAGS[@]}"} >"$OUT/snapshots.log" 2>&1 \
  || { tail -30 "$OUT/snapshots.log"; echo "snapshot run failed" >&2; exit 2; }
# The motion frames of the pairing code are for films, not for comparing.
rm -rf "$SHOTS/frames"
find "$SHOTS" -mindepth 2 -name '*.png' -exec mv {} "$SHOTS/" \; 2>/dev/null || true
find "$SHOTS" -mindepth 1 -type d -exec rm -rf {} + 2>/dev/null || true
echo "== $(ls "$SHOTS" | grep -c '\.png$') pictures in $SHOTS"
if [ "$RECORD" = 1 ]; then
  echo "baseline recorded in $BASELINE"
  exit 0
fi
# The pairing code is new every time it is drawn, and the finished Live Check names a
# random folder: those may change more.
python3 -I "$ROOT/scripts/visual-diff.py" "$BASELINE" "$SHOTS" "$OUT" --no-island \
  --allow popover-pairing=20 --allow sheet-pairing=20 --allow live-check-finished=3
