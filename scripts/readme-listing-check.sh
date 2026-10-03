#!/usr/bin/env bash
# readme-listing-check.sh — does README.md list every tool this repo installs (and nothing that is gone)?
#
# What it checks (offline, bash + awk + grep only):
#   1. tree:     every agents/*.md, commands/*.md and skills/*/ is named in the first fenced block of README.md
#   2. section:  each of them has its own heading  ### `name`  or  ### `/name`
#   3. programs: install.sh and every scripts/*.sh that exists is named in README.md (path as written here)
#   4. stale:    every entry the README tree lists under agents/, commands/, skills/ exists on disk
# Usage:   scripts/readme-listing-check.sh [ROOT]      # ROOT defaults to the repo this script lives in
#          scripts/readme-listing-check.sh --selftest  # proves a complete README passes and three drifts fail
# Output:  one "MISSING <kind>: <name>" or "STALE <kind>: <name>" line per gap, then the last line
#          "readme-listing: ok checks=N" or "readme-listing: FAILED gaps=K checks=N"
# Exit:    0 no gap · 1 gaps (or no README.md) · 2 usage
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
GAPS=0
CHECKS=0

gap() { echo "$*"; GAPS=$((GAPS + 1)); }

# tree_block README — the lines of the first fenced code block
tree_block() {
  awk '/^```/{n++; next} n==1{print} n>=2{exit}' "$1"
}

# tree_entries README — "section<TAB>name" for every child the tree lists under agents/, commands/, skills/
tree_entries() {
  tree_block "$1" | awk '
    index($0, "── ") == 0 { next }
    {
      top = (index($0, "├") == 1 || index($0, "└") == 1)
      line = $0
      sub(/^.*── /, "", line)
      split(line, parts, " ")
      name = parts[1]
      if (top) { section = name; next }
      if (section == "agents/" || section == "commands/" || section == "skills/") print section "\t" name
    }'
}

# has_heading README NAME — a "### `NAME`" or "### `/NAME`" heading exists
has_heading() {
  grep -q -E "^### \`/?$2\`[[:space:]]*$" "$1"
}

run_checks() {
  local root="$1" readme="$1/README.md" block f name section
  GAPS=0
  CHECKS=0
  if [ ! -s "$readme" ]; then
    echo "MISSING file: README.md"
    GAPS=1
    return 1
  fi
  block="$(tree_block "$readme")"

  for f in "$root"/agents/*.md "$root"/commands/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    section="$(basename "$(dirname "$f")")"
    CHECKS=$((CHECKS + 2))
    printf '%s\n' "$block" | grep -q -F -- "── $name" || gap "MISSING tree: $section/$name"
    has_heading "$readme" "${name%.md}" || gap "MISSING section: $section/${name%.md}"
  done
  for f in "$root"/skills/*/; do
    [ -d "$f" ] || continue
    name="$(basename "$f")"
    CHECKS=$((CHECKS + 2))
    printf '%s\n' "$block" | grep -q -F -- "── $name/" || gap "MISSING tree: skills/$name/"
    has_heading "$readme" "$name" || gap "MISSING section: skills/$name"
  done

  for f in "$root/install.sh" "$root"/scripts/*.sh; do
    [ -f "$f" ] || continue
    name="${f#"$root"/}"
    CHECKS=$((CHECKS + 1))
    grep -q -F -- "$name" "$readme" || gap "MISSING program: $name"
  done

  while IFS=$'\t' read -r section name; do
    [ -n "$name" ] || continue
    CHECKS=$((CHECKS + 1))
    [ -e "$root/$section${name%/}" ] || gap "STALE tree: $section$name"
  done < <(tree_entries "$readme")

  [ "$GAPS" -eq 0 ]
}

report() {
  if run_checks "$1"; then
    echo "readme-listing: ok checks=$CHECKS"
  else
    echo "readme-listing: FAILED gaps=$GAPS checks=$CHECKS"
    return 1
  fi
}

# write_readme FILE SKILLS... — a README that lists agent a, command c and the given skills
write_readme() {
  local out="$1" s
  shift
  {
    printf '# fixture\n\n```\nfixture/\n├── agents/\n│   └── a.md        # agent\n├── commands/\n│   └── c.md        # command\n├── skills/\n'
    for s in "$@"; do printf '│   ├── %s/        # skill\n' "$s"; done
    printf '├── scripts/\n│   └── gate.sh\n└── install.sh\n```\n\n### `a`\n\n### `/c`\n\n'
    for s in "$@"; do printf '### `/%s`\n\n' "$s"; done
    printf 'Gate: `scripts/gate.sh`\n'
  } > "$out"
}

selftest() {
  local t rc=0 out
  t="$(mktemp -d)"
  mkdir -p "$t/good/agents" "$t/good/commands" "$t/good/skills/x" "$t/good/skills/y" "$t/good/scripts"
  printf 'a\n' > "$t/good/agents/a.md"
  printf 'c\n' > "$t/good/commands/c.md"
  printf 'x\n' > "$t/good/skills/x/SKILL.md"
  printf 'y\n' > "$t/good/skills/y/SKILL.md"
  printf '#!/usr/bin/env bash\n' > "$t/good/install.sh"
  printf '#!/usr/bin/env bash\n' > "$t/good/scripts/gate.sh"
  cp -r "$t/good" "$t/drift"
  cp -r "$t/good" "$t/stale"
  cp -r "$t/good" "$t/program"
  cp -r "$t/good" "$t/none"

  # 1. complete README: 2 skills + agent + command = 8 checks, 2 programs, 4 tree entries = 14
  write_readme "$t/good/README.md" x y
  out="$(report "$t/good")" || { echo "selftest FAIL: complete README rejected: $out"; rc=1; }
  [ "${out##*$'\n'}" = "readme-listing: ok checks=14" ] || { echo "selftest FAIL: want 14 checks, got: ${out##*$'\n'}"; rc=1; }

  # 2. drift: skill y exists on disk but the README names only x -> tree + section gap
  write_readme "$t/drift/README.md" x
  out="$(report "$t/drift")" && { echo "selftest FAIL: unlisted skill accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "MISSING tree: skills/y/" || { echo "selftest FAIL: no tree gap for y"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "MISSING section: skills/y" || { echo "selftest FAIL: no section gap for y"; rc=1; }
  printf '%s\n' "$out" | grep -q "FAILED gaps=2 " || { echo "selftest FAIL: want gaps=2, got: ${out##*$'\n'}"; rc=1; }

  # 3. stale: the README lists skill z that is not on disk
  write_readme "$t/stale/README.md" x y z
  out="$(report "$t/stale")" && { echo "selftest FAIL: stale tree entry accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "STALE tree: skills/z/" || { echo "selftest FAIL: no stale line for z"; rc=1; }

  # 4. program: a second script exists that the README does not name
  write_readme "$t/program/README.md" x y
  printf '#!/usr/bin/env bash\n' > "$t/program/scripts/other.sh"
  out="$(report "$t/program")" && { echo "selftest FAIL: undocumented script accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "MISSING program: scripts/other.sh" || { echo "selftest FAIL: no program gap"; rc=1; }

  # 5. no README at all
  out="$(report "$t/none")" && { echo "selftest FAIL: missing README accepted"; rc=1; }

  rm -rf "$t"
  [ "$rc" -eq 0 ] && echo "selftest ok (5 cases)"
  return "$rc"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$SELF"; exit 0 ;;
  -*) echo "readme-listing-check.sh: unknown option $1" >&2; exit 2 ;;
esac
ROOT="${1:-$(cd "$(dirname "$SELF")/.." && pwd)}"
[ -d "$ROOT" ] || { echo "readme-listing-check.sh: not a directory: $ROOT" >&2; exit 2; }
report "$ROOT"
