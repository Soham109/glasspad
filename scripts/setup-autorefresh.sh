#!/usr/bin/env bash
# One-time setup: your Mac renews Glasspad on your iPhone automatically, so the free-account
# 7-day limit never bites. Installs a LaunchAgent (a background job macOS runs for you,
# ~/Library/LaunchAgents/com.soham109.glasspad.refresh.plist) that runs
# scripts/refresh-phone.sh from this checkout every hour. Run scripts/install-phone.sh once first.
#
# Usage: scripts/setup-autorefresh.sh [--remove]
#   --remove  Turn automatic renewal off and delete the LaunchAgent.
set -euo pipefail
case "${1:-}" in -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;; esac
cd "$(dirname "$0")/.."
LABEL="com.soham109.glasspad.refresh"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
DOMAIN="gui/$(id -u)"

if [ "${1:-}" = "--remove" ]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Automatic renewal removed."
  exit 0
fi

[ -f "${HOME}/Library/Application Support/Glasspad/phone-install.env" ] || {
  echo "Install once first with scripts/install-phone.sh (phone plugged in), then run this again."; exit 1; }

# The path goes into XML, so &, < and > must be escaped.
SCRIPT="$(printf '%s' "$PWD/scripts/refresh-phone.sh" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
NEW="$(cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>${SCRIPT}</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
</dict>
</plist>
XML
)"
if [ -f "$PLIST" ] && [ "$(cat "$PLIST")" = "$NEW" ] && launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  echo "Automatic renewal is already on."
  exit 0
fi
mkdir -p "$(dirname "$PLIST")"
printf '%s\n' "$NEW" > "$PLIST"
plutil -lint "$PLIST" >/dev/null
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Automatic renewal is on. Your Mac checks hourly and renews when the install is 5 days old."
echo "Log: ~/Library/Logs/Glasspad/refresh.log"
