#!/usr/bin/env bash
# Makes the files attached to a GitHub release, from a tag:
#   glasspad-<version>.tar.gz   the source code at that tag (git archive)
#   SHA256SUMS                  its SHA-256 checksum, checkable with: shasum -a 256 -c SHA256SUMS
# Before that it checks that the tag and project.yml's MARKETING_VERSION (the apps' version) agree,
# so a release never ships with a stale version number. It also warns when the website's
# VERSION in web/site/pages.ts differs (the site can be updated after the tag, so it only warns).
# Usage: scripts/release/package.sh v0.2.1 [output folder, default build/release]
set -euo pipefail
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ $# -lt 1 ] || [ $# -gt 2 ]; then
  sed -n '2,8s/^# \{0,1\}//p' "$0"; [ $# -ge 1 ] && [ $# -le 2 ]; exit $?
fi
cd "$(dirname "$0")/../.."
tag="$1"
out="${2:-build/release}"
version="${tag#v}"
case "$tag" in v[0-9]*.[0-9]*.[0-9]*) ;; *) echo "Tag $tag is not of the form v1.2.3." >&2; exit 1 ;; esac
git rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null || { echo "No tag $tag here." >&2; exit 1; }

app_version="$(git show "$tag:project.yml" | sed -nE 's/^ *MARKETING_VERSION: *"?([0-9A-Za-z.-]+)"?.*/\1/p' | head -1)"
web_version="$(git show "$tag:web/site/pages.ts" | sed -nE 's/^export const VERSION = "([^"]+)".*/\1/p' | head -1)"
[ "$app_version" = "$version" ] || { echo "project.yml MARKETING_VERSION is $app_version, the tag says $version." >&2; exit 1; }
if [ "$web_version" != "$version" ]; then
  msg="web/site/pages.ts VERSION is $web_version at $tag, not $version: the website still names the old version."
  # On GitHub Actions this shows as a warning on the run's summary page.
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning file=web/site/pages.ts::$msg"; else echo "Warning: $msg" >&2; fi
fi

mkdir -p "$out"
name="glasspad-$version"
git archive --format=tar.gz --prefix="$name/" -o "$out/$name.tar.gz" "$tag"
(cd "$out" && shasum -a 256 "$name.tar.gz" > SHA256SUMS && shasum -a 256 -c SHA256SUMS >/dev/null)
echo "Made $out/$name.tar.gz and $out/SHA256SUMS:"
cat "$out/SHA256SUMS"
