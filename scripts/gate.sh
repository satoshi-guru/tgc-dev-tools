#!/usr/bin/env bash
# gate.sh — offline gate for tgc-dev-tools (fleet board gate, routing["gates"]).
#
# What it checks (no internet, no dependencies beyond bash/python3 + the store's agent-file-check):
#   1. bash -n over install.sh and every scripts/*.sh
#   2. agents/*.md and skills/*/SKILL.md carry YAML frontmatter with name + description;
#      commands/*.md are non-empty
#   3. .claude/agents/*.md pass ~/.claude/scripts/dev/agent-file-check.py (skipped with a note if the store is absent).
#      The checker is started in the repo root, because it looks up the paths an agent file names in its working
#      directory (issue #21: started elsewhere, the gate was red on a good tree or green on a broken one)
#   4. install.sh into a temp dir installs every agent, command and skill dir of this repo (counts match),
#      copies every entry of a skill (hidden ones too) except its evals/, and leaves an evals/ folder that a
#      destination already had as it was (issue #8)
#   5. install.sh has no default destination (static read of the file; the gate never runs it without one)
#   6. README.md lists every agent, command, skill and script (scripts/readme-listing-check.sh; skipped without README.md)
#   7. README.md carries no `git push` command whose target is main (issue #16; one FAIL per command line, with the
#      number of the line where the command starts; a quoted command counts too, the check cannot read a "never" in
#      front of it; skipped without README.md). Since issue #18 also: a command wrapped with a backslash, options
#      between git and push (git -C dir push ...), --all / --mirror / --branches, and a push without a ref after a
#      switch or checkout to main in the same code block. Since issue #30 also: git called by its path
#      (/usr/bin/git push ...), a ref or command in single quotes, and lines that end in a carriage return (CRLF)
# Usage:  scripts/gate.sh            # run from anywhere; last line "gate: ok" (exit 0) or "gate: FAILED" (exit 1)
#          scripts/gate.sh --selftest # proves the checks fail on 12 broken fixtures and pass on 7 good ones (+ 29 line cases and 86 block cases for check 7)
#          of these, one broken and one good fixture belong to check 3; they are skipped with a note if the store is absent
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
# the store program of check 3; one place, because the selftest skips its check 3 cases exactly when check 3 is skipped
AGENT_CHECKER="$HOME/.claude/scripts/dev/agent-file-check.py"
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
# word the part after the last ":" is the target.
# Also reported since issue #18 (the number is the line where the command starts, the text is the joined command):
#   - a wrapped command: a line that ends in a backslash is joined with the next one before the words are split
#     (not across a code fence)
#   - options between git and push: every -word is skipped, and with -C -c --git-dir --work-tree --namespace
#     --config-env the word after it as well (git -C dir push origin main)
#   - --all, --mirror, --branches (the newer name of --all), whatever the remote: they push main without naming it
#   - a push without a ref while main is checked out: after `git switch main` / `git checkout main` (also -c / -b /
#     -C / -B with the new name main) a `git push` with no ref word (nothing, or only the remote), or with the ref
#     HEAD / @, is reported. The state lives inside one fenced code block (``` or ~~~) and ends with it; outside a
#     fence it lives for one line. A switch or checkout to another branch, a new branch or --detach clears it;
#     `git checkout -- path` leaves it. `git push --tags` without a ref pushes tags only and is left alone; the word
#     after -o / --push-option / --receive-pack / --exec is an option value, not the remote.
# Also reported since issue #30:
#   - git called by its path: a command word that ends in /git (/usr/bin/git, ./git, ~/bin/git) is read like git.
#     A word that only ends in the letters git (legit, my-git, x/.git) is not, and a path or URL that ends in /git
#     matters only when the word after it (options aside) is push, switch or checkout
#   - single quotes: they are stripped like double quotes, around the ref (git push origin 'main') and around a
#     whole command (sh -c 'git switch main && git push')
#   - CRLF line endings: carriage returns at the end of a line are dropped before the line is read, so the last
#     word is main and not main + carriage return, a backslash in front of the carriage return still joins the
#     lines, and the reported text carries none
# Still not seen: an indented code block (four blanks or a tab, no fence) - a switch to main in one of its lines
# and a push without a ref in the next are two lines outside a fence, so the state is gone (the fourth form of
# issue #30, left out there on purpose because it changes how the state is scoped; now issue #32); git reached
# through a variable, a command substitution or a quoted command word ("$GIT" push, $(command -v git) push,
# "/usr/bin/git" push - issue #33); a file whose only line ends are bare carriage returns (one line for awk,
# also issue #33); a branch change by other means (git switch --track origin/main,
# git branch -M main, git clone, git worktree, cd into another clone), `git checkout <path>` without "--" (read as
# a branch, clears the state), state carried from one code block to the next, a push configured elsewhere
# (push.default, remote.*.push, an alias), and prose: the check reads commands, not sentences.
readme_push_main() {
  awk '
    function issep(t) { return (t == "&&" || t == "||" || t == "|" || t == ";" || t == "`" || t ~ /^#/) }
    # \047 is the single quote: the awk program itself stands in single quotes, so it cannot be written literally
    function bare(t) { gsub(/^["\047(]+|[.,:;!?)"\047]+$/, "", t); return t }
    { s = $0; sub(/\r+$/, "", s); L[NR] = s }
    END {
      fence = 0; onmain = 0; found = 0
      for (r = 1; r <= NR; r = nx) {
        # one logical line: the physical lines r .. nx-1, joined where a line ends in a backslash
        n = 0; text = ""; nx = r
        do {
          s = L[nx]; cont = 0
          if (s ~ /\\$/ && nx < NR && L[nx + 1] !~ /^[ \t]*(```|~~~)/) {
            cont = 1; sub(/[ \t]*\\$/, "", s)
          }
          if (nx > r) sub(/^[ \t]+/, "", s)
          text = (nx == r) ? s : text " " s
          gsub(/`/, " ` ", s); gsub(/;/, " ; ", s)
          m = split(s, w, /[ \t]+/)
          for (k = 1; k <= m; k++) if (w[k] != "") { tok[++n] = w[k]; tl[n] = nx }
          nx++
        } while (cont)
        if (L[r] ~ /^[ \t]*(```|~~~)/) { fence = !fence; onmain = 0 }
        else if (!fence) onmain = 0
        hit = 0
        for (i = 1; i < n && !hit; i++) {
          # the command word: git at the start of the word, after a character that is no part of a name ("git,
          # (git, `git), or after a slash (/usr/bin/git, ./git) - not legit, my-git, .git
          if (tok[i] !~ /(^|[^A-Za-z0-9_.\/-]|\/)git$/) continue
          k = i + 1
          while (k <= n && tok[k] ~ /^-/) {
            k += (tok[k] ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--config-env)$/) ? 2 : 1
          }
          if (k > n) continue
          cmd = tok[k]; ended = 0
          # "push." / "push)" / "push" + quote in a sentence, a subshell or a quoted command: the command ends at the
          # word itself
          if (cmd ~ /^(push|switch|checkout)[.,:;!?)"\047]+$/) { ended = 1; cmd = bare(cmd) }
          if (cmd == "push") {
            pos = 0; tags = 0
            for (j = k + 1; j <= n && !ended && !hit; j++) {
              t = tok[j]
              if (issep(t)) break
              t = bare(t)
              if (t == "") continue
              if (t ~ /^-/) {
                if (t == "--all" || t == "--mirror" || t == "--branches") hit = 1
                else if (t == "--tags") tags = 1
                else if (t ~ /^(-o|--push-option|--receive-pack|--exec)$/ && j < n && !issep(tok[j + 1])) j++
                continue
              }
              pos++
              if (pos > 1) {
                sub(/^\+/, "", t)
                head = (t == "HEAD" || t == "@")
                sub(/^.*:/, "", t); sub(/^refs\/heads\//, "", t)
                if (t == "main" || (onmain && head)) hit = 1
              }
            }
            if (!hit && onmain && pos <= 1 && !tags) hit = 1
            if (hit) at = tl[i]
          } else if (cmd == "switch" || cmd == "checkout") {
            first = ""; paths = 0; detach = 0
            for (j = k + 1; j <= n && !ended; j++) {
              t = tok[j]
              if (issep(t)) break
              t = bare(t)
              if (t == "") continue
              if (t == "--") { paths = 1; break }
              if (t ~ /^-./) { if (t == "--detach" || t == "-d") detach = 1; continue }
              if (first == "") first = t
            }
            if (detach) onmain = 0
            else if (!paths && first != "") onmain = (first == "main")
          }
        }
        if (hit) { print at ": " text; found = 1 }
      }
      exit found ? 0 : 1
    }
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

  local checker="$AGENT_CHECKER" out
  if [ -d "$root/.claude/agents" ] && [ -f "$checker" ]; then
    # issue #21: the checker looks up the paths an agent file names in its working directory, so it is started in
    # the root that is checked. The $( ) is a subshell: the working directory of the gate's caller stays as it was.
    if ! out="$(cd "$root" && python3 "$checker" .claude/agents --sections "" --model sonnet,opus,haiku,inherit 2>&1)"; then
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
  # line cases for check 7, straight at readme_push_main: 14 lines it must report, 15 it must leave alone. Since
  # issue #30 each list has one line that calls git by its path, one with the ref in single quotes and one that ends
  # in a carriage return (a file saved with CRLF line endings). A here-document line cannot carry a carriage return,
  # so that pair is written with printf right below its list.
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
/usr/bin/git push origin main
git push origin 'main'
EOF
  printf 'git push origin main\r\n' > "$t/line.md"
  readme_push_main "$t/line.md" >/dev/null || { echo "selftest FAIL: push to main not seen: git push origin main + carriage return"; rc=1; }
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
/usr/bin/git push origin feat/x
git push origin 'feat/x'
EOF
  printf 'git push origin feat/x\r\n' > "$t/line.md"
  readme_push_main "$t/line.md" >/dev/null && { echo "selftest FAIL: no push to main, but reported: git push origin feat/x + carriage return"; rc=1; }
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
  # block cases for check 7 (issue #30), three more forms. R is a carriage return, FR a code fence that ends in one.
  local R=$'\r' FR
  FR="$F$R"
  # form 5 — git called by its path (a command word that ends in /git): 5 reported, 7 left alone. A word that only
  # ends in the letters git (legit, my-git, .git) is still no command, and a path that ends in /git is one only when
  # the word after it (options aside) is push, switch or checkout.
  push_block 1 '/usr/bin/git push origin main' || rc=1
  push_block 1 './git push -u origin HEAD:main' || rc=1
  push_block 1 '(/usr/bin/git -C ../x push origin main)' || rc=1
  push_block 1 'Then run `/usr/local/bin/git push --all`.' || rc=1
  push_block 3 "$F" '/usr/bin/git switch main' '/usr/bin/git push' "$F" || rc=1
  push_block '' '/usr/bin/git push -u origin feat/x' || rc=1
  push_block '' '/usr/bin/git pull origin main' || rc=1
  push_block '' 'git clone https://example.org/git main' || rc=1
  push_block '' 'git -C ../git push origin feat/x' || rc=1
  push_block '' 'git push origin feat/git' || rc=1
  push_block '' 'legit push origin main' || rc=1
  push_block '' './my-git push origin main' || rc=1
  # form 6 — single quotes around the ref or around the whole command: 5 reported, 5 left alone
  push_block 1 "git push origin 'main'" || rc=1
  push_block 1 "git push origin 'HEAD:main'" || rc=1
  push_block 1 "sh -c 'git push origin main'" || rc=1
  push_block 1 "sh -c 'git switch main && git push'" || rc=1
  push_block 3 "$F" "git switch 'main'" 'git push' "$F" || rc=1
  push_block '' "git push origin 'feat/x'" || rc=1
  push_block '' "git push origin 'main:feat/x'" || rc=1
  push_block '' "git push origin 'maintenance'" || rc=1
  push_block '' "git commit -m 'main' && git push -u origin feat/x" || rc=1
  push_block '' "sh -c 'git switch feat/x && git push'" || rc=1
  # form 7 — lines that end in a carriage return (CRLF line endings): 6 reported, 5 left alone. The sixth reported
  # one (the ref is not the last word of the line) was seen before issue #30 too; it is here because the issue names
  # it as not measured.
  push_block 1 "git push origin main$R" || rc=1
  push_block 1 "git push -u origin HEAD:main$R" || rc=1
  push_block 1 "git push --all$R" || rc=1
  push_block 1 "git push origin \\$R" "  main$R" || rc=1
  push_block 3 "$FR" "git switch main$R" "git push$R" "$FR" || rc=1
  push_block 1 "git push origin main && echo done$R" || rc=1
  push_block '' "git push -u origin feat/x$R" || rc=1
  push_block '' "git push origin maintenance$R" || rc=1
  push_block '' "git push -u origin \\$R" "  feat/x$R" || rc=1
  push_block '' "$FR" "git switch main$R" "git switch feat/x$R" "git push$R" "$FR" || rc=1
  push_block '' "$FR" "git switch main$R" "$FR" "$R" "$FR" "git push$R" "$FR" || rc=1
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
  # pushcrlf / pushcrlfbranch (issue #30): the listed README with CRLF line endings on every line, plus a push block
  # (block at line 20, command at 21). Before issue #30 the last word of the command was "main" + carriage return and
  # the whole file passed check 7. The FAIL line names line 21 and carries no carriage return; the same file with a
  # push of a branch stays accepted.
  cp -r "$t/listed" "$t/pushcrlf"
  {
    while IFS= read -r line; do printf '%s\r\n' "$line"; done < "$t/listed/README.md"
    printf '\r\n```bash\r\ngit push origin main\r\n```\r\n'
  } > "$t/pushcrlf/README.md"
  out="$(run_checks "$t/pushcrlf")"
  case "$out" in
    *"FAIL: README.md:21: git push to main"*"$R"*) echo "selftest FAIL: the FAIL line for a CRLF README carries a carriage return"; rc=1 ;;
    *"FAIL: README.md:21: git push to main"*) ;;
    *) echo "selftest FAIL: README with CRLF line endings and 'git push origin main' accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushcrlfbranch"
  {
    while IFS= read -r line; do printf '%s\r\n' "$line"; done < "$t/listed/README.md"
    printf '\r\n```bash\r\ngit push -u origin feat/x\r\n```\r\n'
  } > "$t/pushcrlfbranch/README.md"
  out="$(run_checks "$t/pushcrlfbranch")" || {
    echo "selftest FAIL: README with CRLF line endings and 'git push -u origin feat/x' rejected:"
    printf '%s\n' "$out"
    rc=1
  }
  # cwdagent / cwdagentbad (check 3, issue #21): agent-file-check.py looks up the paths an agent file names in its
  # working directory, so the gate has to start it in the root it checks - otherwise the result depends on where the
  # gate was started. Both fixtures are the good one plus a .claude/agents/r.md that names
  # `docs/gate-cwd-case/marker.md`.
  #   cwdagent:    the path exists below the fixture; run_checks is started in an empty directory -> accepted
  #                (check 3 in the caller's directory: "Pfad fehlt", gate red on a good tree - the case of the issue)
  #   cwdagentbad: the path is missing below the fixture; run_checks is started in a directory that has it
  #                -> rejected by check 3 (check 3 in the caller's directory: gate green on a broken tree)
  # The caller's working directory is the same after run_checks as before.
  # Without the store program check 3 is skipped with a note, and so are these cases.
  if [ -f "$AGENT_CHECKER" ]; then
    cp -r "$t/good" "$t/cwdagent"
    mkdir -p "$t/cwdagent/.claude/agents" "$t/cwdagent/docs/gate-cwd-case" "$t/elsewhere" "$t/decoy/docs/gate-cwd-case"
    printf -- '---\nname: r\ndescription: selftest role file for check 3\nmodel: sonnet\ntools: Read\n---\n# Role r\n\nRead first: `docs/gate-cwd-case/marker.md`.\n' > "$t/cwdagent/.claude/agents/r.md"
    printf 'marker\n' > "$t/cwdagent/docs/gate-cwd-case/marker.md"
    out="$(cd "$t/elsewhere" && run_checks "$t/cwdagent" 2>&1)" || {
      echo "selftest FAIL: agent file whose named path exists below the checked root rejected when started in another directory:"
      printf '%s\n' "$out"
      rc=1
    }
    ( cd "$t/elsewhere" && here="$(pwd)" && { run_checks "$t/cwdagent" >/dev/null 2>&1; [ "$(pwd)" = "$here" ]; } ) || {
      echo "selftest FAIL: run_checks left its caller in another working directory"; rc=1; }
    cp -r "$t/good" "$t/cwdagentbad"
    mkdir -p "$t/cwdagentbad/.claude/agents"
    cp "$t/cwdagent/.claude/agents/r.md" "$t/cwdagentbad/.claude/agents/r.md"
    printf 'marker\n' > "$t/decoy/docs/gate-cwd-case/marker.md"
    out="$(cd "$t/decoy" && run_checks "$t/cwdagentbad" 2>&1)" && {
      echo "selftest FAIL: agent file whose named path is missing below the checked root accepted when started in a directory that has it"; rc=1; }
    printf '%s\n' "$out" | grep -q 'FAIL: agent-file-check on .claude/agents' || {
      echo "selftest FAIL: cwdagentbad not rejected by check 3"; rc=1; }
  else
    echo "selftest note: the check 3 cases cwdagent and cwdagentbad skipped (no store program agent-file-check.py)"
  fi
  rm -rf "$t"
  [ "$rc" -eq 0 ] && echo "selftest ok"
  return "$rc"
}

if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
if run_checks "$ROOT"; then echo "gate: ok"; else echo "gate: FAILED"; exit 1; fi
