#!/usr/bin/env bash
# Prints the CHANGELOG.md section for one version, without its "## [x.y.z] - date" heading.
# The release workflow uses it as the GitHub release text.
# Usage: scripts/release/notes.sh 0.2.1   (a leading "v" is fine)
# Exits 1 when CHANGELOG.md has no section for that version, or the section is empty.
set -euo pipefail
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ $# -ne 1 ]; then
  sed -n '2,5s/^# \{0,1\}//p' "$0"; [ $# -eq 1 ]; exit $?
fi
cd "$(dirname "$0")/../.."
version="${1#v}"
notes="$(awk -v v="$version" '
  /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
  found && !/^\[[^]]+\]: / { print }   # skip Markdown link definitions such as [0.2.1]: https://...
  END { if (!found) exit 2 }
' CHANGELOG.md)" || { echo "CHANGELOG.md has no \"## [$version]\" section." >&2; exit 1; }
# Drop blank lines at the start and end.
notes="$(printf '%s\n' "$notes" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
[ -n "$notes" ] || { echo "The CHANGELOG.md section for $version is empty." >&2; exit 1; }
printf '%s\n' "$notes"
