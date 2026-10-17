#!/usr/bin/env bash
# Rewrites the theme list in web/src/themes.ts from the app's theme catalog
# (Packages/GlasspadKit/Sources/GlasspadKit/Theme). Run it after adding or changing a theme.
# Needs swiftc (Xcode or the command line tools). Changes only web/src/themes.ts.
#
# Usage: scripts/web-themes.sh
set -euo pipefail
case "${1:-}" in -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;; esac
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swiftc -O -o "$work/web-themes" Packages/GlasspadKit/Sources/GlasspadKit/Theme/*.swift scripts/web-themes/main.swift
"$work/web-themes" > "$work/list"
# Replace what sits between the list's first and last lines.
awk -v list="$work/list" '
  /^export const THEMES: Theme\[\] = \[$/ { print; while ((getline line < list) > 0) print line; skip = 1; next }
  skip && /^\];$/ { skip = 0 }
  !skip { print }
' web/src/themes.ts > "$work/themes.ts"
mv "$work/themes.ts" web/src/themes.ts
echo "web/src/themes.ts: $(grep -c '^  { key:' web/src/themes.ts) themes"
