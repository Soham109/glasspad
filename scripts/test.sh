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
  if ! (cd "$pkg" && swift test --scratch-path "$GP_BUILD_ROOT/$name" ${GP_SWIFT_FLAGS[@]+"${GP_SWIFT_FLAGS[@]}"} "$@"); then
    failed+=("$name")
  fi
done
if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
