#!/usr/bin/env bash
# Sets each tracked file's modified time to the time of the last commit that changed it.
# A fresh checkout stamps every file with "now", which makes SwiftPM rebuild everything even
# when a cached build folder is restored. With commit times, files that did not change since
# the cached build keep their old times and are skipped. Needs the full history
# (actions/checkout with fetch-depth: 0). Files with local edits keep their current time.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
dirty="$(git status --porcelain --untracked-files=no | cut -c4-)"
# One pass over the history, newest first: the first time a path appears is its last change.
# --first-parent -m lists what each merge brought in, so a conflict fix in a merge counts too.
git log --first-parent -m --format='@%ct' --name-only --no-renames HEAD | awk -v dirty="$dirty" '
  BEGIN { n = split(dirty, d, "\n"); for (i = 1; i <= n; i++) skip[d[i]] = 1 }
  /^@/ { t = substr($0, 2); next }
  NF && !($0 in seen) { seen[$0] = 1; if (!($0 in skip)) print t "\t" $0 }
' | while IFS=$'\t' read -r t path; do
  if [ -f "$path" ]; then touch -h -t "$(date -r "$t" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$t" +%Y%m%d%H%M.%S)" "$path"; fi
done
