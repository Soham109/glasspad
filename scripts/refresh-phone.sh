#!/usr/bin/env bash
# Renews the iPhone install before the free-account 7-day limit. Run hourly by the LaunchAgent
# from scripts/setup-autorefresh.sh; does nothing until the install is 5 days old.
# Reinstalls the exact revision you last installed, so an unfinished update never reaches the phone.
set -uo pipefail
STATE="${HOME}/Library/Application Support/Glasspad/phone-install.env"
LOG_DIR="${HOME}/Library/Logs/Glasspad"
mkdir -p "$LOG_DIR"
exec >>"$LOG_DIR/refresh.log" 2>&1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

notify() { osascript -e "display notification \"$1\" with title \"Glasspad\"" >/dev/null 2>&1 || true; }

[ -f "$STATE" ] || { echo "$(date) no install recorded yet; run scripts/install-phone.sh once"; exit 0; }
# shellcheck disable=SC1090
source "$STATE"
AGE_DAYS=$(( ( $(date +%s) - GLASSPAD_INSTALLED_AT ) / 86400 ))
[ "${1:-}" = "--now" ] || [ "$AGE_DAYS" -ge 5 ] || exit 0

# The same states install-phone.sh accepts. A plain "available" would also match "unavailable".
if ! xcrun devicectl list devices 2>/dev/null | grep "$GLASSPAD_DEVICE" | grep -qE 'available \(paired\)| connected '; then
  echo "$(date) iPhone not reachable (install is $AGE_DAYS days old); will retry next hour"
  [ "$AGE_DAYS" -ge 6 ] && notify "Glasspad expires soon. Bring your iPhone onto this Mac's Wi-Fi so it can renew."
  exit 0
fi

echo "$(date) renewing ${GLASSPAD_REV:0:7} on $GLASSPAD_DEVICE (install is $AGE_DAYS days old)"
if GLASSPAD_TEAM="$GLASSPAD_TEAM" GLASSPAD_REV="$GLASSPAD_REV" "$GLASSPAD_REPO/scripts/install-phone.sh" "$GLASSPAD_DEVICE"; then
  notify "Renewed on your iPhone for another 7 days."
else
  echo "$(date) renewal failed"
  notify "Could not renew on your iPhone. See ~/Library/Logs/Glasspad/refresh.log"
fi
