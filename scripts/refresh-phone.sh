#!/usr/bin/env bash
# Renews the iPhone install before the free-account 7-day limit. Run hourly by the LaunchAgent
# from scripts/setup-autorefresh.sh; does nothing until the install is 5 days old.
# Reinstalls the exact revision you last installed, so an unfinished update never reaches the phone.
set -uo pipefail
STATE="${HOME}/Library/Application Support/Glasspad/phone-install.env"
LOG_DIR="${HOME}/Library/Logs/Glasspad"
mkdir -p "$LOG_DIR"
exec >>"$LOG_DIR/refresh.log" 2>&1
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

notify() { osascript -e "display notification \"$1\" with title \"Glasspad\"" >/dev/null 2>&1 || true; }

[ -f "$STATE" ] || { echo "$(date) no install recorded yet; run scripts/install-phone.sh once"; exit 0; }
GLASSPAD_DEVELOPER_DIR=""
# shellcheck disable=SC1090
source "$STATE"
# The Xcode the install was made with, even if xcode-select points at the command line tools.
if [ -n "$GLASSPAD_DEVELOPER_DIR" ] && [ -d "$GLASSPAD_DEVELOPER_DIR" ]; then export DEVELOPER_DIR="$GLASSPAD_DEVELOPER_DIR"; fi
AGE_DAYS=$(( ( $(date +%s) - GLASSPAD_INSTALLED_AT ) / 86400 ))
[ "${1:-}" = "--now" ] || [ "$AGE_DAYS" -ge 5 ] || exit 0

# Asking the iPhone itself is the one reachability test that reads the same on every Xcode.
if ! xcrun devicectl device info details --device "$GLASSPAD_DEVICE" --timeout 30 >/dev/null 2>&1; then
  echo "$(date) iPhone not reachable (install is $AGE_DAYS days old); will retry next hour"
  [ "$AGE_DAYS" -ge 6 ] && notify "Glasspad expires soon. Bring your iPhone onto this Mac's Wi-Fi so it can renew."
  exit 0
fi

# Reinstalling closes the app, so wait while it is open on the iPhone. The free install stops
# working at 7 days, so in its 7th day (6 full days old) renew anyway and say so.
PROCS="$(mktemp)"
if xcrun devicectl device info processes --device "$GLASSPAD_DEVICE" --timeout 30 --quiet --json-output "$PROCS" >/dev/null 2>&1 \
   && grep -q '/Glasspad\.app/Glasspad"' "$PROCS"; then
  rm -f "$PROCS"
  if [ "${1:-}" != "--now" ] && [ "$AGE_DAYS" -lt 6 ]; then
    echo "$(date) Glasspad is open on the iPhone (install is $AGE_DAYS days old); will retry next hour"
    exit 0
  fi
  echo "$(date) Glasspad is open on the iPhone, but the install expires within a day; renewing anyway"
  notify "Renewing Glasspad on your iPhone now so it does not expire. It will close for a moment."
fi
rm -f "$PROCS"

echo "$(date) renewing ${GLASSPAD_REV:0:7} on $GLASSPAD_DEVICE (install is $AGE_DAYS days old)"
if GLASSPAD_TEAM="$GLASSPAD_TEAM" GLASSPAD_REV="$GLASSPAD_REV" "$GLASSPAD_REPO/scripts/install-phone.sh" "$GLASSPAD_DEVICE"; then
  notify "Renewed on your iPhone for another 7 days."
else
  echo "$(date) renewal failed"
  notify "Could not renew on your iPhone. See ~/Library/Logs/Glasspad/refresh.log"
fi
