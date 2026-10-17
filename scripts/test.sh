#!/usr/bin/env bash
# Run every package's tests. Works with Xcode or with only the command line tools.
# Honours an existing DEVELOPER_DIR (for example DEVELOPER_DIR=/Library/Developer/CommandLineTools
# when Xcode is installed but its license is not accepted yet).
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/toolchain.sh
source scripts/toolchain.sh
# Runs every package even if one fails, then exits non-zero if any failed.
failed=()
for pkg in Packages/*/; do
  echo "== $pkg"
  name="$(basename "$pkg")"
  log="$(mktemp)"
  if ! (cd "$pkg" && swift test --scratch-path "$GP_BUILD_ROOT/$name" ${GP_SWIFT_FLAGS[@]+"${GP_SWIFT_FLAGS[@]}"} "$@") 2>&1 | tee "$log"; then
    # On CI only: hosted machines stall for seconds at random, which trips timing tests. Each
    # failed test gets one more run on its own; it must pass then, and the log names it.
    retry="$(grep -oE '✘ Test [A-Za-z0-9_]+\(' "$log" | sed -E 's/✘ Test ([A-Za-z0-9_]+)\(/\1/' | sort -u | paste -sd '|' -)"
    if [ -n "${CI:-}" ] && [ -n "$retry" ] && [ "$(printf %s "$retry" | tr '|' '\n' | wc -l)" -le 5 ] \
      && (cd "$pkg" && swift test --scratch-path "$GP_BUILD_ROOT/$name" ${GP_SWIFT_FLAGS[@]+"${GP_SWIFT_FLAGS[@]}"} --filter "($retry)\\(" "$@"); then
      echo "RETRIED ON CI AND PASSED ($name): ${retry//|/, }"
    else
      failed+=("$name")
    fi
  fi
  rm -f "$log"
done
# The installer scripts, against fake Apple tools (no iPhone or Apple account needed).
echo "== installer"
if ! /bin/bash scripts/tests/installer-test.sh; then failed+=("installer"); fi
# No call that can block on the main thread (the menu bar icon froze once that way).
echo "== main thread"
if ! python3 -I scripts/check-main-thread.py --self-test || ! python3 -I scripts/check-main-thread.py; then
  failed+=("main-thread")
fi
if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
