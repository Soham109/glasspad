#!/usr/bin/env bash
# Opt-in checks for code style and syntax. Nothing here rewrites a file. `make lint` runs this.
#
# Usage: scripts/lint.sh [--layout] [FILE...]
#
#   (no arguments)  every check below, over every tracked file
#   FILE...         only the Swift check, only on these files (for example the ones you changed)
#   --layout        also list each Swift layout finding (indentation, line breaks, spacing)
#
# Checks:
#   swift        swift-format, which ships with the Swift toolchain (nothing to install). Settings
#                are in .swift-format at the repo root. Two kinds of finding:
#                  rule findings    code patterns, such as an assignment used as a value. These fail.
#                  layout findings  where swift-format's own printer would put spaces and line
#                                   breaks. The code was not written with that printer, so these are
#                                   counted, not enforced. Match the file around new code; do not
#                                   reformat whole files.
#   shell        bash -n (syntax) on install.sh and every script under scripts/.
#   ShellCheck   errors fail, warnings are shown. Skipped when it is not installed
#                (brew install shellcheck).
#   python       syntax of every tracked .py file (parsed, not run).
#   web          the TypeScript type check (tsc --noEmit). Skipped until web/node_modules exists
#                (cd web && npm ci).
#
# Exit 0 when every check that ran passed, 1 when one failed, 2 when swift format is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

show_layout=0
case "${1:-}" in
  -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
  --layout) show_layout=1; shift ;;
esac

if ! swift format --version >/dev/null 2>&1; then
  echo "swift format is not available. It ships with Swift 6 (Xcode 16 or later, or the command line tools)." >&2
  exit 2
fi

failed=()
count() { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }

# --- Swift
swift_files=()
if [ $# -gt 0 ]; then
  for f in "$@"; do case "$f" in *.swift) [ -f "$f" ] && swift_files+=("$f") ;; esac; done
else
  while IFS= read -r f; do swift_files+=("$f"); done < <(git ls-files '*.swift')
fi
echo "== swift"
if [ ${#swift_files[@]} -eq 0 ]; then
  echo "   no Swift files to check"
else
  out="$(mktemp)"
  trap 'rm -f "$out"' EXIT
  # swift-format exits non-zero when it finds anything; the counts below decide the result.
  swift format lint --configuration .swift-format --parallel "${swift_files[@]}" >"$out" 2>&1 || true
  layout='\[(Indentation|AddLines|RemoveLine|LineLength|Spacing|TrailingComma|TrailingWhitespace)\]'
  rules="$(grep -E 'warning: \[' "$out" | grep -vE "$layout" | sort -u || true)"
  layout_lines="$(grep -E "$layout" "$out" | sort -u || true)"
  errors="$(grep -E 'error:' "$out" | sort -u || true)"
  if [ -n "$errors" ]; then echo "$errors"; fi
  if [ "$show_layout" = 1 ] && [ -n "$layout_lines" ]; then echo "$layout_lines"; fi
  if [ -n "$rules" ]; then echo "$rules"; fi
  echo "   ${#swift_files[@]} files: $(count "$rules") rule findings, $(count "$layout_lines") layout findings (not enforced)"
  if [ "$show_layout" = 0 ] && [ -n "$layout_lines" ]; then
    printf '%s\n' "$layout_lines" | grep -oE "$layout" | sort | uniq -c | sort -rn | sed 's/^/   /'
  fi
  if [ -n "$rules" ] || [ -n "$errors" ]; then failed+=("swift"); fi
fi

# With file arguments, only the Swift check runs.
if [ $# -eq 0 ]; then
  shell_files=(install.sh scripts/*.sh scripts/tests/*.sh scripts/tests/stubs/*)

  echo "== shell"
  bad=0
  for f in "${shell_files[@]}"; do bash -n "$f" || bad=1; done
  if [ "$bad" = 1 ]; then failed+=("shell"); else echo "   ${#shell_files[@]} files: syntax ok"; fi

  echo "== shellcheck"
  if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x --shell=bash -S warning install.sh scripts/*.sh scripts/tests/*.sh; then
      echo "   ok"
    elif shellcheck -x --shell=bash -S error install.sh scripts/*.sh scripts/tests/*.sh >/dev/null; then
      echo "   warnings above (not enforced)"
    else
      failed+=("shellcheck")
    fi
  else
    echo "   skipped: shellcheck is not installed (brew install shellcheck)"
  fi

  echo "== python"
  py_files=()
  while IFS= read -r f; do py_files+=("$f"); done < <(git ls-files '*.py')
  if [ ${#py_files[@]} -gt 0 ]; then
    if python3 -I -c 'import ast, sys
for f in sys.argv[1:]:
    with open(f, encoding="utf-8") as fh:
        ast.parse(fh.read(), f)' "${py_files[@]}"; then
      echo "   ${#py_files[@]} files: syntax ok"
    else
      failed+=("python")
    fi
  fi

  echo "== web"
  if [ -d web/node_modules ]; then
    if (cd web && npx --no-install tsc --noEmit); then echo "   types ok"; else failed+=("web"); fi
  else
    echo "   skipped: run (cd web && npm ci) first"
  fi
fi

if [ ${#failed[@]} -gt 0 ]; then
  echo "lint FAILED: ${failed[*]}"
  exit 1
fi
echo "lint: ok"
