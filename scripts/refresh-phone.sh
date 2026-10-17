#!/usr/bin/env bash
# Renews the iPhone install before the free-account 7-day limit. Run hourly by the LaunchAgent
# from scripts/setup-autorefresh.sh; does nothing until the install is 5 days old.
# Reinstalls the exact revision you last installed, so an unfinished update never reaches the phone.
# Each run leaves its outcome in refresh-status.json, which the Mac app shows in Settings > iPhone.
# All output goes to ~/Library/Logs/Glasspad/refresh.log, not the terminal.
#
# Usage: scripts/refresh-phone.sh [--now]
#   --now  Renew now, whatever the install's age and even while the app is in use.
#
# No `set -e`: a failed step must still reach the end, write its status and notify you.
set -uo pipefail
case "${1:-}" in -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;; esac
SUPPORT="${HOME}/Library/Application Support/Glasspad"
STATE="$SUPPORT/phone-install.env"
STATUS="$SUPPORT/refresh-status.json"
SESSION="$SUPPORT/phone-session.json"
LOG_DIR="${HOME}/Library/Logs/Glasspad"
mkdir -p "$LOG_DIR"
exec >>"$LOG_DIR/refresh.log" 2>&1
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

notify() { osascript -e "display notification \"$1\" with title \"Glasspad\"" >/dev/null 2>&1 || true; }
# status RESULT: renewed, waitingInUse, notReachable, failed or tooEarly. Written whole, then
# moved into place, so the Mac app never reads half a file.
status() {
  printf '{"checkedAt":%s,"result":"%s","installedAt":%s}\n' "$(date +%s)" "$1" "$GLASSPAD_INSTALLED_AT" \
    > "$STATUS.tmp" && mv -f "$STATUS.tmp" "$STATUS"
}
# The Mac app writes phone-session.json when a phone connects ({"active":true}) and when it
# leaves ({"active":false,"endedAt":<seconds>}). No session for 30 minutes means the app on the
# iPhone is only suspended, so renewing closes nothing anyone is using. A missing or unreadable
# file, or a session still marked active (even an old one, from a Mac app that has since
# stopped), counts as in use.
phone_idle() {
  [ -f "$SESSION" ] || return 1
  [ "$(plutil -extract active raw -o - "$SESSION" 2>/dev/null)" = false ] || return 1
  local ended
  ended="$(plutil -extract endedAt raw -o - "$SESSION" 2>/dev/null)"
  case "$ended" in ''|*[!0-9]*) return 1 ;; esac
  [ $(( $(date +%s) - ended )) -ge 1800 ]
}

[ -f "$STATE" ] || { echo "$(date) no install recorded yet; run scripts/install-phone.sh once"; exit 0; }
GLASSPAD_DEVELOPER_DIR=""
# shellcheck disable=SC1090
source "$STATE"
# The Xcode the install was made with, even if xcode-select points at the command line tools.
if [ -n "$GLASSPAD_DEVELOPER_DIR" ] && [ -d "$GLASSPAD_DEVELOPER_DIR" ]; then export DEVELOPER_DIR="$GLASSPAD_DEVELOPER_DIR"; fi
AGE_DAYS=$(( ( $(date +%s) - GLASSPAD_INSTALLED_AT ) / 86400 ))
[ "${1:-}" = "--now" ] || [ "$AGE_DAYS" -ge 5 ] || { status tooEarly; exit 0; }

# Asking the iPhone itself is the one reachability test that reads the same on every Xcode.
if ! xcrun devicectl device info details --device "$GLASSPAD_DEVICE" --timeout 30 >/dev/null 2>&1; then
  echo "$(date) iPhone not reachable (install is $AGE_DAYS days old); will retry next hour"
  status notReachable
  [ "$AGE_DAYS" -ge 6 ] && notify "Glasspad expires soon. Bring your iPhone onto this Mac's Wi-Fi so it can renew."
  exit 0
fi

# Reinstalling closes the app. A suspended app is still a process, so an open app is only
# waited for while it is in use. The free install stops working at 7 days, so in its 7th day
# (6 full days old) renew anyway and say so.
PROCS="$(mktemp)"
if xcrun devicectl device info processes --device "$GLASSPAD_DEVICE" --timeout 30 --quiet --json-output "$PROCS" >/dev/null 2>&1 \
   && grep -q '/Glasspad\.app/Glasspad"' "$PROCS"; then
  rm -f "$PROCS"
  if phone_idle; then
    echo "$(date) Glasspad is open on the iPhone but not in use for 30 minutes; renewing"
  elif [ "${1:-}" != "--now" ] && [ "$AGE_DAYS" -lt 6 ]; then
    echo "$(date) Glasspad is in use on the iPhone (install is $AGE_DAYS days old); will retry next hour"
    status waitingInUse
    exit 0
  else
    echo "$(date) Glasspad is in use on the iPhone, but the install expires within a day; renewing anyway"
    notify "Renewing Glasspad on your iPhone now so it does not expire. It will close for a moment."
  fi
fi
rm -f "$PROCS"

echo "$(date) renewing ${GLASSPAD_REV:0:7} on $GLASSPAD_DEVICE (install is $AGE_DAYS days old)"
if GLASSPAD_TEAM="$GLASSPAD_TEAM" GLASSPAD_REV="$GLASSPAD_REV" "$GLASSPAD_REPO/scripts/install-phone.sh" "$GLASSPAD_DEVICE"; then
  # shellcheck disable=SC1090
  source "$STATE"   # the new install time
  status renewed
  notify "Renewed on your iPhone for another 7 days."
else
  echo "$(date) renewal failed"
  status failed
  notify "Could not renew on your iPhone. See ~/Library/Logs/Glasspad/refresh.log"
fi
