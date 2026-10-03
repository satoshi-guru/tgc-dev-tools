#!/usr/bin/env bash
# gate.sh — offline gate for tgc-dev-tools (fleet board gate, routing["gates"]).
#
# What it checks (no internet, no dependencies beyond bash/python3 + the store's agent-file-check):
#   1. bash -n over install.sh and every scripts/*.sh
#   2. agents/*.md and skills/*/SKILL.md carry YAML frontmatter with name + description;
#      commands/*.md are non-empty
#   3. .claude/agents/*.md pass ~/.claude/scripts/dev/agent-file-check.py (skipped with a note if the store is absent)
#   4. install.sh into a temp dir installs every agent, command and skill dir of this repo (counts match)
#   5. install.sh has no default destination (static read of the file; the gate never runs it without one)
#   6. README.md lists every agent, command, skill and script (scripts/readme-listing-check.sh; skipped without README.md)
# Usage:  scripts/gate.sh            # run from anywhere; last line "gate: ok" (exit 0) or "gate: FAILED" (exit 1)
#          scripts/gate.sh --selftest # proves the checks fail on 3 broken fixtures and pass on 2 good ones
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
FAILS=0

fail() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }

# frontmatter_ok FILE "key key" — file starts with --- and the block holds every key
frontmatter_ok() {
  local file="$1" key block
  [ -s "$file" ] || return 1
  [ "$(head -n1 "$file")" = "---" ] || return 1
  block="$(awk 'NR==1{next} /^---$/{exit} {print}' "$file")"
  for key in $2; do
    printf '%s\n' "$block" | grep -q "^${key}:" || return 1
  done
  return 0
}

run_checks() {
  local root="$1" f
  FAILS=0

  for f in "$root/install.sh" "$root"/scripts/*.sh; do
    [ -f "$f" ] || continue
    bash -n "$f" 2>/dev/null || fail "bash -n ${f#"$root"/}"
  done

  for f in "$root"/agents/*.md "$root"/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    frontmatter_ok "$f" "name description" || fail "frontmatter name/description: ${f#"$root"/}"
  done
  for f in "$root"/commands/*.md; do
    [ -f "$f" ] || continue
    [ -s "$f" ] || fail "empty command file: ${f#"$root"/}"
  done

  local checker="$HOME/.claude/scripts/dev/agent-file-check.py" out
  if [ -d "$root/.claude/agents" ] && [ -f "$checker" ]; then
    if ! out="$(python3 "$checker" "$root/.claude/agents" --sections "" --model sonnet,opus,haiku,inherit 2>&1)"; then
      fail "agent-file-check on .claude/agents"
      printf '%s\n' "$out"
    fi
  else
    echo "note: agent-file-check skipped (no .claude/agents or no store)"
  fi

  if [ -f "$root/install.sh" ]; then
    local tmp w g
    tmp="$(mktemp -d)"
    if bash "$root/install.sh" "$tmp/dest" >/dev/null 2>&1; then
      w="$(find "$root/agents" -maxdepth 1 -name '*.md' | wc -l)/$(find "$root/commands" -maxdepth 1 -name '*.md' | wc -l)/$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      g="$(find "$tmp/dest/agents" -maxdepth 1 -name '*.md' | wc -l)/$(find "$tmp/dest/commands" -maxdepth 1 -name '*.md' | wc -l)/$(find "$tmp/dest/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      [ "$w" = "$g" ] || fail "install.sh counts agents/commands/skills want $w got $g"
    else
      fail "install.sh into temp dir"
    fi
    rm -rf "$tmp"
    # a non-comment "${1:-something}" is a default destination: a bare ./install.sh would write somewhere unasked
    if grep -v '^[[:space:]]*#' "$root/install.sh" | grep -q -E '\$\{1:-[^}]'; then
      fail "install.sh has a default destination (issue #4: the destination must be given)"
    fi
  fi

  local lister
  lister="$(dirname "$SELF")/readme-listing-check.sh"
  if [ -f "$root/README.md" ] && [ -f "$lister" ]; then
    if ! out="$(bash "$lister" "$root" 2>&1)"; then
      fail "README.md listing (scripts/readme-listing-check.sh)"
      printf '%s\n' "$out"
    fi
  fi
  [ "$FAILS" -eq 0 ]
}

selftest() {
  local t rc=0
  t="$(mktemp -d)"
  mkdir -p "$t/good/agents" "$t/good/commands" "$t/good/skills/x" "$t/bad/agents" "$t/bad/commands" "$t/bad/skills"
  printf -- '---\nname: a\ndescription: d\n---\nbody\n' > "$t/good/agents/a.md"
  printf 'cmd\n' > "$t/good/commands/c.md"
  printf -- '---\nname: x\ndescription: d\n---\nbody\n' > "$t/good/skills/x/SKILL.md"
  cp "$(dirname "$SELF")/../install.sh" "$t/good/install.sh"
  printf 'no frontmatter\n' > "$t/bad/agents/a.md"
  printf 'echo "unterminated\n' > "$t/bad/install.sh"
  run_checks "$t/good" >/dev/null || { echo "selftest FAIL: good fixture rejected"; rc=1; }
  run_checks "$t/bad" >/dev/null && { echo "selftest FAIL: bad fixture accepted"; rc=1; }
  # default: good fixture whose install.sh carries a default destination again -> rejected (check 5)
  cp -r "$t/good" "$t/default"
  printf 'DEST="${1:-/nonexistent/.claude}"\n' >> "$t/default/install.sh"
  run_checks "$t/default" >/dev/null && { echo "selftest FAIL: default destination accepted"; rc=1; }
  # listed / drift: good fixture with a README that names everything -> accepted, one that names nothing -> rejected (check 6)
  cp -r "$t/good" "$t/listed"
  printf '# f\n\n```\nf/\n├── agents/\n│   └── a.md\n├── commands/\n│   └── c.md\n├── skills/\n│   └── x/\n└── install.sh\n```\n\n### `a`\n\n### `/c`\n\n### `/x`\n' > "$t/listed/README.md"
  run_checks "$t/listed" >/dev/null || { echo "selftest FAIL: listed fixture rejected"; rc=1; }
  cp -r "$t/good" "$t/drift"
  printf '# f\n\nnothing listed, install.sh\n' > "$t/drift/README.md"
  run_checks "$t/drift" >/dev/null && { echo "selftest FAIL: README drift accepted"; rc=1; }
  rm -rf "$t"
  [ "$rc" -eq 0 ] && echo "selftest ok"
  return "$rc"
}

if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
if run_checks "$ROOT"; then echo "gate: ok"; else echo "gate: FAILED"; exit 1; fi
