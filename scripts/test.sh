#!/usr/bin/env bash
# Run every package's tests. Works with Xcode or with only the command line tools.
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
FLAGS=()
if ! xcode-select -p | grep -q Xcode.app; then
  FLAGS=(-Xswiftc "-F$F" -Xlinker "-F$F" -Xlinker -rpath -Xlinker "$F")
fi
for pkg in Packages/*/; do
  echo "== $pkg"
  (cd "$pkg" && swift test "${FLAGS[@]}" "$@")
done
