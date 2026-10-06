#!/usr/bin/env bash
# readme-listing-check.sh — does README.md list every tool this repo installs (and nothing that is gone)?
#
# What it checks (offline, bash + awk + grep only):
#   1. tree:     every agents/*.md, commands/*.md and skills/*/ is named in the first fenced block of README.md
#   2. section:  each of them has its own heading  ### `name`  or  ### `/name`
#   3. programs: install.sh and every scripts/*.sh that exists is named in README.md (path as written here)
#   4. stale:    every entry the README tree lists under agents/, commands/, skills/ exists on disk
# Usage:   scripts/readme-listing-check.sh [ROOT]      # ROOT defaults to the repo this script lives in (also through a symlink)
#          scripts/readme-listing-check.sh --selftest  # 6 cases: a complete README passes, four kinds of drift fail, 10 starts through symlinks (issue #35)
# Output:  one "MISSING <kind>: <name>" or "STALE <kind>: <name>" line per gap, then the last line
#          "readme-listing: ok checks=N" or "readme-listing: FAILED gaps=K checks=N"
# Exit:    0 no gap · 1 gaps (or no README.md) · 2 usage
set -uo pipefail

# real_path FILE — absolute path of FILE with every symlink resolved (issue #35; the function scripts/gate.sh
# carries since issue #29): a link to the file by readlink (a chain of at most 40 links, relative targets read from
# the link's own directory), a link in the directory part by cd -P. Only bash and readlink.
real_path() {
  local p="$1" d t n=0
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do
    d="$(cd -P "$(dirname "$p")" && pwd)" || return 1
    t="$(readlink "$p")" || return 1
    case "$t" in /*) p="$t" ;; *) p="$d/$t" ;; esac
    n=$((n + 1))
  done
  d="$(cd -P "$(dirname "$p")" && pwd)" || return 1
  printf '%s/%s\n' "$d" "$(basename "$p")"
}

# Superseded by issue #35 (started through a symlink, SELF was the link and the default ROOT the directory above it):
# SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SELF="$(real_path "${BASH_SOURCE[0]}")" || { echo "readme-listing-check.sh: cannot resolve its own path: ${BASH_SOURCE[0]}" >&2; exit 2; }
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

# link_case WHAT DIR WANT TEXT PATH [ARG ...] — selftest helper (issue #35; the form of link_case in scripts/gate.sh):
# starts the program file PATH with bash in the directory DIR. WANT is "<last output line> exit=N"; a non-empty TEXT
# must be a whole line of the output as well. Prints the difference and returns 1 when it does not hold.
link_case() {
  local what="$1" dir="$2" want="$3" text="$4" out code got
  shift 4
  out="$(cd "$dir" && bash "$@" 2>&1)"
  code=$?
  got="${out##*$'\n'} exit=$code"
  if [ "$got" != "$want" ]; then
    echo "selftest FAIL: $what: want '$want' got '$got'"
    return 1
  fi
  if [ -n "$text" ] && ! printf '%s\n' "$out" | grep -q -x -F -- "$text"; then
    echo "selftest FAIL: $what: the output lacks the line '$text':"
    printf '%s\n' "$out"
    return 1
  fi
  return 0
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

  # 6. started through symlinks (issue #35): the program file itself, started with bash and without ROOT in an
  #    empty directory, directly and through links - the answer is that of the repo the file belongs to, never
  #    that of the directory above the link. Four trees, each with a last line of its own:
  #      linkrepo     the good fixture plus scripts/ with a copy of this file         ok checks=15
  #      linkrepobad  the same plus a skill z the README does not name               FAILED gaps=2 checks=17
  #      overgood     a complete tree with one skill and no scripts/ of its own      ok checks=12
  #      overbad      the same plus a skill w the README does not name               FAILED gaps=2 checks=14
  #    overgood / overbad are the directories the links are put into; a program that takes the directory above
  #    the link reads these instead (green on the link to linkrepobad, red on the link to linkrepo).
  #    10 starts: 2 direct, 2 through a file link in an otherwise empty directory (the measured case of the
  #    issue), 2 through a file link inside overgood / overbad, 1 through a link with a relative target, 1 through
  #    a link to a link, 2 through a link to the scripts/ directory.
  local d ok='readme-listing: ok checks=15 exit=0' bad='readme-listing: FAILED gaps=2 checks=17 exit=1'
  local why='MISSING tree: skills/z/'
  cp -r "$t/good" "$t/linkrepo"
  cp "$SELF" "$t/linkrepo/scripts/readme-listing-check.sh"
  printf 'Lister: `scripts/readme-listing-check.sh`\n' >> "$t/linkrepo/README.md"
  cp -r "$t/linkrepo" "$t/linkrepobad"
  mkdir -p "$t/linkrepobad/skills/z"
  printf 'z\n' > "$t/linkrepobad/skills/z/SKILL.md"
  for d in overgood overbad; do
    mkdir -p "$t/$d/agents" "$t/$d/commands" "$t/$d/skills/x" "$t/$d/sub"
    printf 'a\n' > "$t/$d/agents/a.md"
    printf 'c\n' > "$t/$d/commands/c.md"
    printf 'x\n' > "$t/$d/skills/x/SKILL.md"
    printf '#!/usr/bin/env bash\n' > "$t/$d/install.sh"
    write_readme "$t/$d/README.md" x
    printf 'Lister: `scripts/readme-listing-check.sh`\n' >> "$t/$d/README.md"
  done
  mkdir -p "$t/overbad/skills/w"
  printf 'w\n' > "$t/overbad/skills/w/SKILL.md"
  mkdir -p "$t/cwd" "$t/lone/sub" "$t/rel/sub" "$t/chain/sub"
  ln -s "$t/linkrepo/scripts/readme-listing-check.sh" "$t/lone/sub/lister.sh"
  ln -s "$t/linkrepobad/scripts/readme-listing-check.sh" "$t/lone/sub/lister-bad.sh"
  ln -s "$t/linkrepobad/scripts/readme-listing-check.sh" "$t/overgood/sub/lister.sh"
  ln -s "$t/linkrepo/scripts/readme-listing-check.sh" "$t/overbad/sub/lister.sh"
  ln -s ../../linkrepobad/scripts/readme-listing-check.sh "$t/rel/sub/lister.sh"
  ln -s "$t/rel/sub/lister.sh" "$t/chain/sub/lister.sh"
  ln -s "$t/linkrepobad/scripts" "$t/overgood/scripts"
  ln -s "$t/linkrepo/scripts" "$t/overbad/scripts"
  link_case "6 direct start, complete tree" "$t/cwd" "$ok" "" "$t/linkrepo/scripts/readme-listing-check.sh" || rc=1
  link_case "6 direct start, tree with a gap" "$t/cwd" "$bad" "$why" "$t/linkrepobad/scripts/readme-listing-check.sh" || rc=1
  link_case "6 file link in an empty directory, complete tree" "$t/cwd" "$ok" "" "$t/lone/sub/lister.sh" || rc=1
  link_case "6 file link in an empty directory, tree with a gap" "$t/cwd" "$bad" "$why" "$t/lone/sub/lister-bad.sh" || rc=1
  link_case "6 file link to the tree with a gap, placed inside a complete tree" "$t/cwd" "$bad" "$why" "$t/overgood/sub/lister.sh" || rc=1
  link_case "6 file link to the complete tree, placed inside a tree with a gap" "$t/cwd" "$ok" "" "$t/overbad/sub/lister.sh" || rc=1
  link_case "6 file link with a relative target, tree with a gap" "$t/cwd" "$bad" "$why" "$t/rel/sub/lister.sh" || rc=1
  link_case "6 link to a link, tree with a gap" "$t/cwd" "$bad" "$why" "$t/chain/sub/lister.sh" || rc=1
  link_case "6 link to scripts/ of the tree with a gap, placed inside a complete tree" "$t/cwd" "$bad" "$why" "$t/overgood/scripts/readme-listing-check.sh" || rc=1
  link_case "6 link to scripts/ of the complete tree, placed inside a tree with a gap" "$t/cwd" "$ok" "" "$t/overbad/scripts/readme-listing-check.sh" || rc=1

  rm -rf "$t"
  [ "$rc" -eq 0 ] && echo "selftest ok (6 cases)"
  return "$rc"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$SELF"; exit 0 ;;
  -*) echo "readme-listing-check.sh: unknown option $1" >&2; exit 2 ;;
esac
# issue #35: SELF is resolved, so the default is the repo the program file belongs to, however it was started
ROOT="${1:-$(cd -P "$(dirname "$SELF")/.." && pwd)}"
[ -d "$ROOT" ] || { echo "readme-listing-check.sh: not a directory: $ROOT" >&2; exit 2; }
report "$ROOT"
