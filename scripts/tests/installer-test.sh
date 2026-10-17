#!/bin/bash
# Tests install.sh and the phone scripts without a real iPhone, Xcode or Apple account.
# Fake xcrun/devicectl, security, xcodebuild, sudo, curl, brew, launchctl... come first on PATH
# (scripts/tests/stubs) and read their behaviour from files in $STUB. Every run uses a scratch
# HOME whose path has spaces in it, so quoting bugs show up here.
#
# Usage: scripts/tests/installer-test.sh        (bash 3.2 is fine; no other tools needed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STUBS="$HERE/stubs"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/glasspad installer test.XXXXXX")"
ROOT="$(cd "$ROOT" && pwd -P)"
trap 'rm -rf "$ROOT"' EXIT
export STUBS
PASS=0; FAIL=0; CASE=""

# A fake Glasspad upstream: the real phone/renewal scripts, a quick fake Mac build.
UP="$ROOT/up stream"
mkdir -p "$UP/scripts"
cp "$REPO/scripts/install-phone.sh" "$REPO/scripts/setup-autorefresh.sh" "$REPO/scripts/refresh-phone.sh" "$UP/scripts/"
cat > "$UP/scripts/install-mac.sh" <<'EOF'
#!/bin/bash
# Test stand-in for the Mac build: records the call and the state the real one writes.
set -e
cd "$(dirname "$0")/.."
echo "install-mac.sh team=${GLASSPAD_TEAM:-} identity=${GLASSPAD_SIGN_IDENTITY:-}" >> "$STUB/calls"
mkdir -p "$HOME/Library/Application Support/Glasspad"
printf 'GLASSPAD_MAC_REV=%q\n' "$(git rev-parse HEAD)" > "$HOME/Library/Application Support/Glasspad/mac-install.env"
mkdir -p "$GLASSPAD_APP"
EOF
chmod +x "$UP/scripts/"*.sh
( cd "$UP" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
REV="$(git -C "$UP" rev-parse HEAD)"

list_json() { # list_json UDID... : paired physical iPhones
  local d
  printf '{"result":{"devices":['
  printf '{"hardwareProperties":{"reality":"simulated","platform":"iOS","udid":"SIM-1"},"connectionProperties":{"pairingState":"paired"}}'
  for d in "$@"; do
    printf ',{"hardwareProperties":{"reality":"physical","platform":"iOS","deviceType":"iPhone","udid":"%s"},"connectionProperties":{"pairingState":"paired"}}' "$d"
  done
  printf ']}}'
}

# new_case NAME: fresh scratch HOME and stub state with a ready Mac and a ready iPhone.
new_case() {
  CASE="$1"
  T="$ROOT/case $1"; rm -rf "$T"; mkdir -p "$T/home dir" "$T/stub/bin" "$T/Xcode.app/Contents/Developer/usr/bin"
  export STUB="$T/stub" HOME="$T/home dir"
  for f in "$STUBS"/*; do ln -s "$f" "$STUB/bin/$(basename "$f")"; done
  rm "$STUB/bin/brew"   # Homebrew absent unless a case adds it
  # /usr/bin/git forwards to the developer dir, and the tests point DEVELOPER_DIR at a fake Xcode.
  printf '#!/bin/bash\nunset DEVELOPER_DIR\nexec /usr/bin/git "$@"\n' > "$STUB/bin/git"; chmod +x "$STUB/bin/git"
  ln -s "$STUBS/xcodebuild" "$T/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
  touch "$STUB/license_ok" "$STUB/firstlaunch_ok"
  echo "1949B7C39DBCC06E7F1A9D06EB3DF2273A7F0BD7 TEAMAAAAAA alice@example.com" > "$STUB/identities"
  list_json 00008000-0000000000000001 > "$STUB/list.json"
  echo 00008000-0000000000000001 > "$STUB/reachable"
  echo enabled > "$STUB/devmode"
  echo ok > "$STUB/launch"
  : > "$STUB/calls"
  DEST="$T/home dir/Projects/glass pad"
}
# run_installer [env...]: runs install.sh the way the README says (piped into bash), no terminal.
# shellcheck disable=SC2016
run_installer() {
  OUT="$(env PATH="$STUB/bin:/usr/bin:/bin:/usr/sbin:/sbin" GLASSPAD_EXTRA_PATH= \
    GLASSPAD_XCODE="$T/Xcode.app" GLASSPAD_HOME="$DEST" GLASSPAD_REPO_URL="$UP" \
    GLASSPAD_APP="$STUB/Applications/Glasspad.app" GLASSPAD_NONINTERACTIVE=1 GLASSPAD_POLL=0.05 GLASSPAD_WAIT_LIMIT=1 "$@" \
    bash -c 'bash < "$1"' _ "$REPO/install.sh" 2>&1)"
  CODE=$?
}
pass() { PASS=$((PASS+1)); printf '  ok   %s: %s\n' "$CASE" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s: %s\n' "$CASE" "$1"; printf '%s\n' "$OUT" > "$ROOT/out.txt"; tail -n 30 "$ROOT/out.txt" | sed 's/^/       | /'; }
expect_code() { if [ "$CODE" = "$1" ]; then pass "exit code $1"; else bad "exit code $CODE, wanted $1"; fi; }
# Output is searched in a file, never through a pipe: `printf | grep -q` lets grep quit at the
# first match while printf is still writing, printf dies of SIGPIPE, and pipefail turns a found
# line into a "missing" one (this made the suite fail about one run in seven).
has_out() { printf '%s' "$OUT" > "$ROOT/out.txt"; grep -qF -- "$1" "$ROOT/out.txt"; }
expect_out()  { if has_out "$1"; then pass "says \"$1\""; else bad "missing \"$1\""; fi; }
reject_out()  { if has_out "$1"; then bad "should not say \"$1\""; else pass "does not say \"$1\""; fi; }
expect_call() { if grep -qF -- "$1" "$STUB/calls"; then pass "ran \"$1\""; else bad "did not run \"$1\""; fi; }
reject_call() { if grep -qF -- "$1" "$STUB/calls"; then bad "should not run \"$1\""; else pass "did not run \"$1\""; fi; }
STATE_FILE() { printf '%s' "$HOME/Library/Application Support/Glasspad/phone-install.env"; }

echo "== installer tests (scratch: $ROOT)"

new_case "fresh mac"
rm "$STUB/license_ok" "$STUB/firstlaunch_ok"
run_installer
expect_code 2
expect_out "needs your Mac password"
expect_out "sudo \"$T/Xcode.app/Contents/Developer/usr/bin/xcodebuild\" -license accept"
touch "$STUB/sudo_ok"; rm "$STUB/bin/xcodegen"; ln -s "$STUBS/brew" "$STUB/bin/brew"
run_installer
expect_code 0
expect_call "sudo -n $T/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license accept"
expect_out "did not match its published checksum"
expect_call "brew install xcodegen"
expect_call "curl --proto =https --tlsv1.2 -fsSL"
expect_out "XcodeGen 2.46.0"
expect_out "Team TEAMAAAAAA"
expect_call "install-mac.sh team=TEAMAAAAAA identity=1949B7C39DBCC06E7F1A9D06EB3DF2273A7F0BD7"
expect_out "Allow Accessibility"
expect_call "xcrun devicectl device install app --device 00008000-0000000000000001"
expect_out "Glasspad is open on your iPhone"
expect_out "Automatic renewal is on."
expect_out "What is installed:"
if [ -f "$HOME/Library/LaunchAgents/com.soham109.glasspad.refresh.plist" ] \
   && [ "$(plutil -extract ProgramArguments.1 raw "$HOME/Library/LaunchAgents/com.soham109.glasspad.refresh.plist")" = "$DEST/scripts/refresh-phone.sh" ]; then
  pass "renewal agent points at the clone"; else bad "renewal agent path"; fi
# The saved state must read back exactly, spaces and all.
# shellcheck disable=SC1090
got="$( set +u; . "$(STATE_FILE)"; printf '%s|%s|%s' "$GLASSPAD_REPO" "$GLASSPAD_TEAM" "$GLASSPAD_DEVELOPER_DIR")"
if [ "$got" = "$DEST|TEAMAAAAAA|$T/Xcode.app/Contents/Developer" ]; then pass "state file reads back"; else bad "state file: $got"; fi

CASE="everything installed"
: > "$STUB/calls"
run_installer
expect_code 0
expect_out "Already installed (${REV:0:7}), nothing to do"
reject_call "install-mac.sh"
reject_call "device install app"
reject_call "sudo"
reject_out "Allow Accessibility"
expect_out "Automatic renewal is already on."

CASE="local changes"
echo "# edit" >> "$DEST/scripts/install-mac.sh"
run_installer
expect_code 0
expect_out "not committed, so it was not updated"
git -C "$DEST" checkout -q -- scripts/install-mac.sh

new_case "no xcodegen offline"
rm "$STUB/bin/xcodegen"; touch "$STUB/offline"
run_installer
expect_code 1
expect_out "Could not download XcodeGen"
expect_out "Could not install XcodeGen"

new_case "no phone"
list_json > "$STUB/list.json"; : > "$STUB/reachable"
run_installer
expect_code 2
expect_out "Plug your iPhone into this Mac with a cable"
expect_out "GLASSPAD_SKIP_PHONE=1"
reject_out "Developer Mode"

new_case "phone away"
: > "$STUB/reachable"
run_installer
expect_code 2
expect_out "paired but this Mac cannot reach it"

new_case "skip phone"
list_json > "$STUB/list.json"; : > "$STUB/reachable"
run_installer GLASSPAD_SKIP_PHONE=1
expect_code 0
expect_out "Skipped (GLASSPAD_SKIP_PHONE=1)"
expect_out "not set up (needs the iPhone install)"
reject_call "devicectl"

new_case "no developer mode"
echo disabled > "$STUB/devmode"
run_installer
expect_code 2
expect_out "Settings > Privacy & Security > Developer Mode"
reject_call "device install app"
echo "$(( $(cat "$STUB/count.details") + 3 )) enabled" > "$STUB/devmode.after"
run_installer GLASSPAD_WAIT_LIMIT=30
expect_code 0
expect_out "waiting for Developer Mode"
expect_out "Glasspad is open on your iPhone"

new_case "old devicectl text"
echo none > "$STUB/devmode"
run_installer
expect_code 0
expect_out "Glasspad is open on your iPhone"

new_case "untrusted app"
echo untrusted > "$STUB/launch"
run_installer
expect_code 2
expect_out "VPN & Device Management > your Apple ID > Trust"
echo "2 ok" > "$STUB/launch.after"; rm -f "$STUB/count.launch"
run_installer GLASSPAD_WAIT_LIMIT=30
expect_code 0
expect_out "Glasspad is open on your iPhone"

new_case "locked phone"
echo locked > "$STUB/launch"
run_installer
expect_code 2
expect_out "Unlock your iPhone"
reject_out "VPN & Device Management"

new_case "other launch error"
echo weird > "$STUB/launch"
run_installer
expect_code 1
expect_out "something else broke"

new_case "two teams"
printf '%s\n' "1111111111111111111111111111111111111111 TEAMAAAAAA alice@example.com" \
  "2222222222222222222222222222222222222222 TEAMBBBBBB bob@example.com" > "$STUB/identities"
run_installer
expect_code 0
expect_out "more than one Apple team"
expect_out "Team TEAMAAAAAA"
run_installer GLASSPAD_TEAM=TEAMBBBBBB GLASSPAD_FORCE=1
expect_call "install-mac.sh team=TEAMBBBBBB identity=2222222222222222222222222222222222222222"
: > "$STUB/calls"
run_installer GLASSPAD_FORCE=1
expect_out "Team TEAMBBBBBB"   # remembered from the last iPhone install
rm "$(STATE_FILE)"
echo 2 > "$T/answers"
run_installer GLASSPAD_NONINTERACTIVE=0 GLASSPAD_TTY="$T/answers"
expect_out "Which one should sign Glasspad?"
expect_out "Team TEAMBBBBBB"

new_case "no certificate"
: > "$STUB/identities"
run_installer
expect_code 2
expect_out "No Apple Development certificate"

new_case "folder in the way"
mkdir -p "$DEST"; echo hi > "$DEST/notes.txt"
run_installer
expect_code 1
expect_out "is not a copy of Glasspad"

# The renewal job itself.
LOG() { printf '%s' "$HOME/Library/Logs/Glasspad/refresh.log"; }
STATUS() { printf '%s' "$HOME/Library/Application Support/Glasspad/refresh-status.json"; }
SESSION() { printf '%s' "$HOME/Library/Application Support/Glasspad/phone-session.json"; }
age() { sed -i '' "s/^GLASSPAD_INSTALLED_AT=.*/GLASSPAD_INSTALLED_AT=$(( $(date +%s) - $1*3600 ))/" "$(STATE_FILE)"; }
# refresh: one run of the renewal job; OUT is its log, fresh calls and log for each run.
refresh() {
  : > "$STUB/calls"; : > "$(LOG)"; rm -f "$(STATUS)"
  env PATH="$STUB/bin:/usr/bin:/bin" bash "$DEST/scripts/refresh-phone.sh" "$@"
  OUT="$(cat "$(LOG)")"
}
# expect_status RESULT: the outcome the Mac app reads, a fresh check time and the install time.
expect_status() {
  local got at now; now="$(date +%s)"
  got="$(plutil -extract result raw -o - "$(STATUS)" 2>/dev/null)"
  at="$(plutil -extract checkedAt raw -o - "$(STATUS)" 2>/dev/null)"
  if [ "$got" = "$1" ] && [ -n "$at" ] && [ $(( now - at )) -lt 60 ] \
     && [ "$(plutil -extract installedAt raw -o - "$(STATUS)")" = "$( set +u; . "$(STATE_FILE)"; echo "$GLASSPAD_INSTALLED_AT")" ]; then
    pass "status $1"; else bad "status \"$got\" at \"$at\", wanted $1"; fi
}
# session ACTIVE MINUTES_AGO [FILE_HOURS_OLD]: what the Mac app last wrote about the phone.
session() {
  if [ "$1" = true ]; then printf '{"active":true}\n' > "$(SESSION)"
  else printf '{"active":false,"endedAt":%s}\n' "$(( $(date +%s) - $2*60 ))" > "$(SESSION)"; fi
  [ -n "${3:-}" ] && touch -t "$(date -v-"$3"H +%Y%m%d%H%M.%S)" "$(SESSION)"
  return 0
}

new_case "refresh"
run_installer >/dev/null
refresh
reject_call "device install"
expect_status tooEarly
age 144
refresh
expect_out "renewing ${REV:0:7}"
expect_call "xcrun devicectl device install app --device 00008000-0000000000000001"
expect_call "osascript -e display notification \"Renewed on your iPhone"
expect_status renewed
installed="$( set +u; . "$(STATE_FILE)"; echo "$GLASSPAD_INSTALLED_AT")"
if [ $(( $(date +%s) - installed )) -lt 60 ]; then pass "install time moved on"; else bad "install time $installed"; fi

CASE="refresh while app open"
touch "$STUB/app_running"
age 125; refresh
expect_out "Glasspad is in use on the iPhone (install is 5 days old); will retry next hour"
reject_call "device install"
expect_status waitingInUse
age 125; session false 31; refresh
expect_out "not in use for 30 minutes; renewing"
expect_call "device install app"
reject_call "Renewing Glasspad on your iPhone now"
expect_status renewed
age 125; session false 10; refresh
expect_out "will retry next hour"
reject_call "device install"
age 125; session true; refresh
expect_out "will retry next hour"
reject_call "device install"
expect_status waitingInUse
age 125; session true 0 3; refresh   # left active by a Mac app that is no longer running
expect_out "will retry next hour"
reject_call "device install"
age 125; printf 'not json' > "$(SESSION)"; refresh
reject_call "device install"
age 150; session true; refresh
expect_out "renewing anyway"
expect_call "osascript -e display notification \"Renewing Glasspad on your iPhone now"
expect_call "device install app"
expect_status renewed
age 125; session true; refresh --now
expect_call "device install app"
rm "$STUB/app_running" "$(SESSION)"

CASE="refresh fails"
touch "$STUB/install_fails"
age 125; refresh
expect_out "renewal failed"
expect_call "osascript -e display notification \"Could not renew on your iPhone"
expect_status failed
rm "$STUB/install_fails"

CASE="refresh phone away"
: > "$STUB/reachable"
age 150; refresh
expect_out "iPhone not reachable"
expect_call "osascript"
expect_status notReachable

# Installing a fixed release: an upstream with a tagged commit and a newer one after it.
PINNED="$ROOT/up pinned"
git clone -q "$UP" "$PINNED"
git -C "$PINNED" tag v9.9.9
echo "# newer" >> "$PINNED/scripts/install-phone.sh"
git -C "$PINNED" -c user.name=t -c user.email=t@t commit -qam newer
NEWER="$(git -C "$PINNED" rev-parse HEAD)"

new_case "pinned release"
run_installer GLASSPAD_REPO_URL="$PINNED" GLASSPAD_SKIP_PHONE=1 GLASSPAD_REF=v9.9.9
expect_code 0
expect_out "(v9.9.9, ${REV:0:7})"
if [ "$(git -C "$DEST" rev-parse HEAD)" = "$REV" ]; then pass "built the tagged commit"; else bad "HEAD is not the tag"; fi
run_installer GLASSPAD_REPO_URL="$PINNED" GLASSPAD_SKIP_PHONE=1
expect_code 0
expect_out "on a fixed release"
if [ "$(git -C "$DEST" rev-parse HEAD)" = "$REV" ]; then pass "stays on the tag without GLASSPAD_REF"; else bad "moved off the tag"; fi
run_installer GLASSPAD_REPO_URL="$PINNED" GLASSPAD_SKIP_PHONE=1 GLASSPAD_REF="${NEWER:0:12}"
expect_code 0
if [ "$(git -C "$DEST" rev-parse HEAD)" = "$NEWER" ]; then pass "moves to another commit"; else bad "did not move to the commit"; fi
run_installer GLASSPAD_REPO_URL="$PINNED" GLASSPAD_SKIP_PHONE=1 GLASSPAD_REF=v0.0.0-missing
expect_code 1
expect_out "There is no tag or commit named v0.0.0-missing"

new_case "unsafe source"
run_installer GLASSPAD_REPO_URL=http://example.com/glasspad.git
expect_code 1
expect_out "must start with https://"
run_installer GLASSPAD_REPO_URL=git://example.com/glasspad.git
expect_code 1
expect_out "must start with https://"
run_installer GLASSPAD_REF=--upload-pack=touch
expect_code 1
expect_out "is not a tag or commit name"
reject_call "xcodebuild"
if [ -e "$DEST" ]; then bad "made the folder"; else pass "made nothing"; fi

# A download cut off partway must do nothing at all: everything sits inside main(), which only
# runs from the last line.
new_case "half download"
HALF="$ROOT/half.sh"
# shellcheck disable=SC2016
for cut in 200 $(( $(wc -c < "$REPO/install.sh") / 2 )) $(( $(wc -c < "$REPO/install.sh") - 12 )); do
  head -c "$cut" "$REPO/install.sh" > "$HALF"
  OUT="$(env PATH="$STUB/bin:/usr/bin:/bin:/usr/sbin:/sbin" GLASSPAD_XCODE="$T/Xcode.app" GLASSPAD_HOME="$DEST" \
    GLASSPAD_REPO_URL="$UP" GLASSPAD_NONINTERACTIVE=1 bash -c 'bash < "$1"' _ "$HALF" 2>&1)"
  if [ -s "$STUB/calls" ] || [ -e "$DEST" ] || [ -e "$HOME/Library" ]; then
    bad "the first $cut bytes ran something"
  else
    pass "the first $cut bytes ran nothing"
  fi
done

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
