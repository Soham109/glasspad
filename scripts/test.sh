#!/usr/bin/env bash
# Run every package's tests. Works with Xcode or with only the command line tools.
# Honours an existing DEVELOPER_DIR (for example DEVELOPER_DIR=/Library/Developer/CommandLineTools
# when Xcode is installed but its license is not accepted yet).
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/toolchain.sh
source scripts/toolchain.sh
for pkg in Packages/*/; do
  echo "== $pkg"
  name="$(basename "$pkg")"
  (cd "$pkg" && swift test --scratch-path "$GP_BUILD_ROOT/$name" ${GP_SWIFT_FLAGS[@]+"${GP_SWIFT_FLAGS[@]}"} "$@")
done
