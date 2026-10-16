#!/usr/bin/env bash
# The guided live check on this Mac (docs/LIVE-CHECK.md): Glasspad tries each Mac feature for
# real, one step at a time in its own window, puts the Mac back after each one, and writes
# ~/Library/Logs/Glasspad/live-check-<date>.md. Quits the running Glasspad first (the phone
# disconnects) and starts it as usual again when the check is done.
#   --install              build and install this checkout first (scripts/install-mac.sh)
#   --include-disruptive   also Lock Screen, Sleep Display, Sleep Mac, Empty Trash and Eject All
set -euo pipefail
cd "$(dirname "$0")/.."
APP=/Applications/Glasspad.app
BIN="$APP/Contents/MacOS/Glasspad"
LOGS="$HOME/Library/Logs/Glasspad"

install=0
args=(--live-check)
for a in "$@"; do
  case "$a" in
    --install) install=1 ;;
    --include-disruptive) args+=(--include-disruptive) ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $a (try --help)" >&2; exit 2 ;;
  esac
done

if [ "$install" = 1 ]; then scripts/install-mac.sh; fi
if [ ! -x "$BIN" ]; then
  echo "Glasspad is not in /Applications. Run: scripts/live-check.sh --install" >&2
  exit 1
fi
# The installed copy must be new enough to have the check (the test window name is in it).
if ! grep -q -a "Glasspad Live Check" "$BIN"; then
  echo "The Glasspad in /Applications is older than the live check. Run: scripts/live-check.sh --install" >&2
  exit 1
fi

# The installed, signed app keeps its Accessibility and Screen Recording permissions, so the
# check runs there rather than from the build folder.
pkill -f "$BIN" 2>/dev/null || true
for _ in $(seq 50); do pgrep -f "$BIN" >/dev/null || break; sleep 0.1; done

echo "The live check is open in its own window. This waits until you press Done."
open -W -n "$APP" --args "${args[@]}"

open "$APP"
report="$(ls -t "$LOGS"/live-check-*.md 2>/dev/null | head -n 1 || true)"
if [ -n "$report" ]; then
  echo "Report: $report"
else
  echo "No report was written." >&2
fi
