#!/usr/bin/env bash
# One-time setup: your Mac renews Glasspad on your iPhone automatically, so the free-account
# 7-day limit never bites. Removes itself with: scripts/setup-autorefresh.sh --remove
set -euo pipefail
cd "$(dirname "$0")/.."
LABEL="com.soham109.glasspad.refresh"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

if [ "${1:-}" = "--remove" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Automatic renewal removed."
  exit 0
fi

[ -f "${HOME}/Library/Application Support/Glasspad/phone-install.env" ] || {
  echo "Install once first with scripts/install-phone.sh (phone plugged in), then run this again."; exit 1; }

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>${PWD}/scripts/refresh-phone.sh</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Automatic renewal is on. Your Mac checks hourly and renews when the install is 5 days old."
echo "Log: ~/Library/Logs/Glasspad/refresh.log"
