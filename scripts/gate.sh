#!/usr/bin/env bash
# gate.sh — offline gate for tgc-dev-tools (fleet board gate, routing["gates"]).
#
# What it checks (no internet, no dependencies beyond bash/python3 + the store's agent-file-check):
#   1. bash -n over install.sh and every scripts/*.sh
#   2. agents/*.md and skills/*/SKILL.md carry YAML frontmatter with name + description;
#      commands/*.md are non-empty
#   3. .claude/agents/*.md pass ~/.claude/scripts/dev/agent-file-check.py (skipped with a note if the store is absent)
#   4. install.sh into a temp dir installs every agent, command and skill dir of this repo (counts match),
#      copies every entry of a skill (hidden ones too) except its evals/, and leaves an evals/ folder that a
#      destination already had as it was (issue #8)
#   5. install.sh has no default destination (static read of the file; the gate never runs it without one)
#   6. README.md lists every agent, command, skill and script (scripts/readme-listing-check.sh; skipped without README.md)
#   7. README.md carries no `git push` command whose target is main (issue #16; one FAIL per line, with its number;
#      a quoted command counts too, the check cannot read a "never" in front of it; skipped without README.md)
# Usage:  scripts/gate.sh            # run from anywhere; last line "gate: ok" (exit 0) or "gate: FAILED" (exit 1)
#          scripts/gate.sh --selftest # proves the checks fail on 8 broken fixtures and pass on 4 good ones (+ 23 line cases for check 7)
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

# readme_push_main FILE — prints "LINE: text" for every line that carries a `git push` command whose pushed ref or
# refspec target is the whole word main: origin main, -u origin main, HEAD:main, feat/x:main, +main, refs/heads/main,
# :main, --delete main. Returns 0 when at least one such line exists, 1 when there is none.
# How a line is read: words after "git push" up to the end of the command (&& || | ; a comment, or the backtick that
# closes inline code); options are skipped; the first other word is the remote and is skipped too; of every further
# word the part after the last ":" is the target. Not seen: a command wrapped over two lines, `git -C dir push`,
# a push without a ref while main is checked out, --all / --mirror.
readme_push_main() {
  awk '
    {
      line = $0
      gsub(/`/, " ` ", line)
      n = split(line, tok, /[ \t]+/)
      hit = 0
      for (i = 1; i < n && !hit; i++) {
        if (tok[i] !~ /(^|[^A-Za-z0-9_.\/-])git$/ || tok[i + 1] != "push") continue
        pos = 0
        for (j = i + 2; j <= n; j++) {
          t = tok[j]
          if (t == "&&" || t == "||" || t == "|" || t == ";" || t == "`" || t ~ /^#/) break
          last = (t ~ /;$/)
          gsub(/^["(]+|[.,:;!?)"]+$/, "", t)
          if (t != "" && t !~ /^-/) {
            pos++
            if (pos > 1) {
              sub(/^\+/, "", t); sub(/^.*:/, "", t); sub(/^refs\/heads\//, "", t)
              if (t == "main") { hit = 1; break }
            }
          }
          if (last) break
        }
      }
      if (hit) { print NR ": " $0; found = 1 }
    }
    END { exit found ? 0 : 1 }
  ' "$1"
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
      # issue #8 — what the counts do not see. Fresh destination: every entry of a skill arrives (hidden ones
      # too) except its evals/. Destination that already holds skills/<name>/evals/own.json for every skill:
      # after the install each own.json is still there and nothing was added next to it.
      local n own all
      diff -r -x evals "$root/skills" "$tmp/dest/skills" >/dev/null 2>&1 || fail "install.sh did not copy every entry of every skill (evals/ aside, hidden entries included)"
      [ -z "$(find "$tmp/dest/skills" -mindepth 2 -maxdepth 2 -name evals)" ] || fail "install.sh installed a skill's evals/ folder (evals are not installed)"
      for f in "$root"/skills/*/; do
        [ -d "$f" ] || continue
        mkdir -p "$tmp/kept/skills/$(basename "$f")/evals"
        printf 'own\n' > "$tmp/kept/skills/$(basename "$f")/evals/own.json"
      done
      bash "$root/install.sh" "$tmp/kept" >/dev/null 2>&1 || fail "install.sh into a destination that already has evals/ folders"
      n="$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      own="$(find "$tmp/kept/skills" -mindepth 3 -maxdepth 3 -path '*/evals/own.json' | wc -l)"
      all="$(find "$tmp/kept/skills" -mindepth 3 -maxdepth 3 -path '*/evals/*' | wc -l)"
      [ "$own" = "$n" ] || fail "install.sh removed an evals/ folder the destination already had (issue #8): $own of $n own.json left"
      [ "$all" = "$own" ] || fail "install.sh wrote into an evals/ folder the destination already had (issue #8): $all entries, $own of them own.json"
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

  # check 7: README.md must not instruct a git push whose target is main (issue #16)
  if [ -f "$root/README.md" ]; then
    while IFS= read -r out; do
      [ -n "$out" ] || continue
      fail "README.md:${out%%:*}: git push to main (issue #16: main changes only through a merged pull request):${out#*:}"
    done < <(readme_push_main "$root/README.md")
  fi
  [ "$FAILS" -eq 0 ]
}

# fixture_installer FILE SKILL_COPY — writes a minimal installer for the selftest whose skills loop runs
# SKILL_COPY; in it $d is the skill's source dir (with trailing slash) and $o the skill's destination dir
fixture_installer() {
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'DEST="$1"' \
    'S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' \
    'mkdir -p "$DEST/agents" "$DEST/commands" "$DEST/skills"' \
    'cp "$S"/agents/*.md "$DEST/agents/"' \
    'cp "$S"/commands/*.md "$DEST/commands/"' \
    'for d in "$S"/skills/*/; do' \
    '  o="$DEST/skills/$(basename "$d")"' \
    '  mkdir -p "$o"' \
    "  $2" \
    'done' > "$1"
}

# push_block WANT LINE... — selftest helper for check 7 (issue #18): writes the LINEs into a fixture of its own and
# compares the line numbers readme_push_main reports with WANT ("" = nothing reported, "3" = line 3, "3 4" = both).
# Prints the fixture and returns 1 on a difference.
push_block() {
  local want="$1" got="" out f
  shift
  f="$(mktemp)"
  printf '%s\n' "$@" > "$f"
  while IFS= read -r out; do
    got="$got${got:+ }${out%%:*}"
  done < <(readme_push_main "$f")
  rm -f "$f"
  [ "$got" = "$want" ] && return 0
  echo "selftest FAIL: check 7 block case, reported line(s) want '$want' got '$got':"
  printf '    | %s\n' "$@"
  return 1
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
  # withevals: good fixture whose skill carries evals/ and a hidden entry -> accepted; a fresh install of it has
  # the hidden entry and no evals/ (check 4, issue #8)
  local out
  cp -r "$t/good" "$t/withevals"
  mkdir -p "$t/withevals/skills/x/evals"
  printf '{}\n' > "$t/withevals/skills/x/evals/evals.json"
  printf 'keep\n' > "$t/withevals/skills/x/.keep"
  run_checks "$t/withevals" >/dev/null || { echo "selftest FAIL: fixture with evals/ and a hidden entry rejected"; rc=1; }
  bash "$t/withevals/install.sh" "$t/withevals-dest" >/dev/null 2>&1
  [ -f "$t/withevals-dest/skills/x/.keep" ] || { echo "selftest FAIL: hidden entry of a skill not installed"; rc=1; }
  [ ! -e "$t/withevals-dest/skills/x/evals" ] || { echo "selftest FAIL: evals/ of a skill installed"; rc=1; }
  # evalsrm / evalscopied / nohidden: the same fixture with an installer that (a) copies the whole skill dir and
  # then removes evals/ in the destination - the behaviour before issue #8, (b) copies evals/ along, (c) skips
  # evals/ but drops hidden entries -> each rejected, and for its own reason (check 4)
  cp -r "$t/withevals" "$t/evalsrm"
  fixture_installer "$t/evalsrm/install.sh" 'cp -r "$d." "$o/"; rm -rf "$o/evals"'
  out="$(run_checks "$t/evalsrm" 2>&1)" && { echo "selftest FAIL: installer that removes the destination's evals/ accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q 'removed an evals/ folder the destination already had (issue #8)' || { echo "selftest FAIL: evalsrm not rejected for the removed evals/"; rc=1; }
  cp -r "$t/withevals" "$t/evalscopied"
  fixture_installer "$t/evalscopied/install.sh" 'cp -r "$d." "$o/"'
  out="$(run_checks "$t/evalscopied" 2>&1)" && { echo "selftest FAIL: installer that installs evals/ accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q "installed a skill's evals/ folder" || { echo "selftest FAIL: evalscopied not rejected for the installed evals/"; rc=1; }
  cp -r "$t/withevals" "$t/nohidden"
  fixture_installer "$t/nohidden/install.sh" 'for e in "$d"*; do [ "$(basename "$e")" = evals ] || cp -r "$e" "$o/"; done'
  out="$(run_checks "$t/nohidden" 2>&1)" && { echo "selftest FAIL: installer that drops hidden entries accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q 'did not copy every entry of every skill' || { echo "selftest FAIL: nohidden not rejected for the missing hidden entry"; rc=1; }
  # listed / drift: good fixture with a README that names everything -> accepted, one that names nothing -> rejected (check 6)
  cp -r "$t/good" "$t/listed"
  printf '# f\n\n```\nf/\n├── agents/\n│   └── a.md\n├── commands/\n│   └── c.md\n├── skills/\n│   └── x/\n└── install.sh\n```\n\n### `a`\n\n### `/c`\n\n### `/x`\n' > "$t/listed/README.md"
  run_checks "$t/listed" >/dev/null || { echo "selftest FAIL: listed fixture rejected"; rc=1; }
  cp -r "$t/good" "$t/drift"
  printf '# f\n\nnothing listed, install.sh\n' > "$t/drift/README.md"
  run_checks "$t/drift" >/dev/null && { echo "selftest FAIL: README drift accepted"; rc=1; }
  # pushmain / pushrefspec / pushbranch: the listed fixture (check 6 green) plus a push instruction in its README, so
  # only check 7 decides. The two rejected ones must name the line (the block starts at line 20, the command is 21).
  local out line
  cp -r "$t/listed" "$t/pushmain"
  printf '\n```bash\ngit push origin main\n```\n' >> "$t/pushmain/README.md"
  out="$(run_checks "$t/pushmain")"
  case "$out" in
    *"FAIL: README.md:21: git push to main"*) ;;
    *) echo "selftest FAIL: README with 'git push origin main' accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushrefspec"
  printf '\n```bash\ngit push origin HEAD:main\n```\n' >> "$t/pushrefspec/README.md"
  out="$(run_checks "$t/pushrefspec")"
  case "$out" in
    *"FAIL: README.md:21: git push to main"*) ;;
    *) echo "selftest FAIL: README with 'git push origin HEAD:main' accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushbranch"
  printf '\nThe change reaches `main` through a pull request, never by a push to `main`:\n\n```bash\ngit push -u origin feat/x\n```\n' >> "$t/pushbranch/README.md"
  run_checks "$t/pushbranch" >/dev/null || { echo "selftest FAIL: README with 'git push -u origin feat/x' rejected"; rc=1; }
  # line cases for check 7, straight at readme_push_main: 11 lines it must report, 12 it must leave alone
  while IFS= read -r line; do
    printf '%s\n' "$line" > "$t/line.md"
    readme_push_main "$t/line.md" >/dev/null || { echo "selftest FAIL: push to main not seen: $line"; rc=1; }
  done <<'EOF'
git push origin main
git push -u origin main
git push origin HEAD:main
git push origin feat/x:main
git push --force origin +main
git push origin refs/heads/main
git push origin :main
git push origin --delete main
git push origin feat/x main
git fetch origin && git push origin main
Then run `git push origin main`.
EOF
  while IFS= read -r line; do
    printf '%s\n' "$line" > "$t/line.md"
    readme_push_main "$t/line.md" >/dev/null && { echo "selftest FAIL: no push to main, but reported: $line"; rc=1; }
  done <<'EOF'
git push -u origin feat/x
git push origin maintenance
git push origin feat/main-menu
git push origin main:feat/x
git push main feat/x
git push origin feat/x && git switch main
git push origin feat/x; git switch main
git push origin feat/x # then a pull request against main
git switch main && git pull --ff-only origin main
never by a push to `main`
`git push` the branch, then open a pull request against main
`main` changes only through a merged pull request: the branch is pushed, `main` is not
EOF
  # block cases for check 7 (issue #18), straight at readme_push_main through push_block: the first argument is the
  # line number(s) that must be reported ('' = nothing), the rest are the lines of the fixture. F is a code fence.
  local F='```'
  # form 1 — a command wrapped with a backslash: 4 reported (at the line where the command starts), 4 left alone
  push_block 1 'git push origin \' '  main' || rc=1
  push_block 1 'git push \' '  -u origin \' '  HEAD:main' || rc=1
  push_block 2 'git fetch origin && \' '  git push origin main' || rc=1
  push_block 3 'git push -u origin \' '  feat/x' 'git push origin main' || rc=1
  push_block '' 'git push -u origin \' '  feat/x' || rc=1
  push_block '' 'git push -u origin feat/x \' '  && git switch main' || rc=1
  push_block '' 'git push -u \' '  origin \' '  main:feat/x' || rc=1
  push_block '' "$F" 'git switch main \' "$F" 'git push' || rc=1
  # form 2 — options between git and push: 4 reported, 4 left alone
  push_block 1 'git -C ../x push origin main' || rc=1
  push_block 1 'git -c a=b push origin HEAD:main' || rc=1
  push_block 1 'git --git-dir ../x/.git --work-tree=../x push origin main' || rc=1
  push_block 1 'Then run `git --no-pager push -u origin main`.' || rc=1
  push_block '' 'git -C ../x push -u origin feat/x' || rc=1
  push_block '' 'git -C ../x pull origin main' || rc=1
  push_block '' 'git -C main push origin feat/x' || rc=1
  push_block '' 'git -C push pull origin main' || rc=1
  # form 3 — --all / --mirror (and --branches, the newer name of --all): 5 reported, 6 left alone
  push_block 1 'git push --all' || rc=1
  push_block 1 'git push origin --mirror' || rc=1
  push_block 1 'git push --all origin' || rc=1
  push_block 1 'git push --branches origin' || rc=1
  push_block 1 'Then run `git push --all`.' || rc=1
  push_block '' 'git push --tags origin feat/x' || rc=1
  push_block '' 'git push --force-with-lease origin feat/x' || rc=1
  push_block '' 'git fetch --all' || rc=1
  push_block '' 'git fetch --all && git push -u origin feat/x' || rc=1
  push_block '' 'git push origin feat/all' || rc=1
  push_block '' 'git push origin feat/x # --all and --mirror are rejected' || rc=1
  # form 4 — a push without a ref while main is checked out, inside one code block: 12 reported, 14 left alone
  push_block 3 "$F" 'git switch main' 'git push' "$F" || rc=1
  push_block 3 "$F" 'git checkout main' 'git push origin' "$F" || rc=1
  push_block 3 "$F" 'git switch main && git pull --ff-only origin main' 'git push' "$F" || rc=1
  push_block 2 "$F" 'git switch main && git push' "$F" || rc=1
  push_block 1 'git checkout main && git push origin' || rc=1
  push_block 2 "$F" '(git switch main && git push)' "$F" || rc=1
  push_block '3 4' "$F" 'git switch main' 'git push' 'git push origin' "$F" || rc=1
  push_block 3 "$F" 'git switch main' 'git push -u origin HEAD' "$F" || rc=1
  push_block 3 "$F" 'git switch main' 'git push --force-with-lease' "$F" || rc=1
  push_block 3 "$F" 'git switch main' 'git push -o ci.skip origin' "$F" || rc=1
  push_block 3 "$F" 'git checkout -B main origin/main' 'git push' "$F" || rc=1
  push_block 4 "$F" 'git switch main' 'git checkout -- README.md' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch -c feat/x --no-track origin/main' 'git push -u origin feat/x' "$F" || rc=1
  push_block '' "$F" 'git switch main && git pull --ff-only origin main' './install.sh /tmp/a/.claude' './install.sh /tmp/b/.claude' "$F" || rc=1
  push_block '' "$F" 'git add README.md' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git switch feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git switch -c feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git checkout main' 'git checkout -b feat/x' 'git push origin' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git switch --detach origin/main' 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' "$F" '' "$F" 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git push -u origin feat/x' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git push origin HEAD:feat/x' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git push -o ci.skip origin feat/x' "$F" || rc=1
  push_block '' "$F" 'git switch main' 'git push origin --tags' "$F" || rc=1
  push_block '' "$F" 'git switch maintenance' 'git push' "$F" || rc=1
  push_block '' 'After `git switch main` the install runs.' 'Then `git push` the branch.' || rc=1
  # pushwrapped / pushonmain / pushflow: the same through run_checks, like pushmain above (block at line 20). The
  # wrapped command is named at the line where it starts (21), the push without a ref at its own line (22); the
  # step-3 block of the real README (switch to main, pull, install) stays accepted.
  cp -r "$t/listed" "$t/pushwrapped"
  printf '\n```bash\ngit push origin \\\n  main\n```\n' >> "$t/pushwrapped/README.md"
  out="$(run_checks "$t/pushwrapped")"
  case "$out" in
    *"FAIL: README.md:21: git push to main"*) ;;
    *) echo "selftest FAIL: README with a wrapped 'git push origin main' accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushonmain"
  printf '\n```bash\ngit switch main\ngit push\n```\n' >> "$t/pushonmain/README.md"
  out="$(run_checks "$t/pushonmain")"
  case "$out" in
    *"FAIL: README.md:22: git push to main"*) ;;
    *) echo "selftest FAIL: README with 'git switch main' + 'git push' in one block accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushflow"
  printf '\n```bash\ngit switch main && git pull --ff-only origin main\n./install.sh /tmp/x/.claude\n```\n' >> "$t/pushflow/README.md"
  run_checks "$t/pushflow" >/dev/null || { echo "selftest FAIL: README with 'git switch main && git pull' + install rejected"; rc=1; }
  rm -rf "$t"
  [ "$rc" -eq 0 ] && echo "selftest ok"
  return "$rc"
}

if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
if run_checks "$ROOT"; then echo "gate: ok"; else echo "gate: FAILED"; exit 1; fi
