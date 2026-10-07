#!/usr/bin/env bash
# gate.sh — offline gate for tgc-dev-tools (fleet board gate, routing["gates"]).
#
# What it checks (no internet, no dependencies beyond bash/python3 + the store's agent-file-check):
#   0. the root is a checkout of this repo: it has install.sh and README.md (issue #29). A root without them is
#      rejected and nothing else is checked or run there - before, nearly every check was skipped on such a root and
#      the gate was green on a directory it had not looked at. The root is the repo this file belongs to: a symlink
#      to this file or to scripts/ is resolved first (before, the root was the directory above the link)
#   1. bash -n over install.sh and every scripts/*.sh
#   2. agents/*.md and skills/*/SKILL.md carry YAML frontmatter with name + description;
#      commands/*.md are non-empty
#   3. .claude/agents/*.md pass ~/.claude/scripts/dev/agent-file-check.py (skipped with a note if the store is absent).
#      The checker is started in the repo root, because it looks up the paths an agent file names in its working
#      directory (issue #21: started elsewhere, the gate was red on a good tree or green on a broken one)
#   4. install.sh into a temp dir installs every agent, command and skill dir of this repo (counts match),
#      copies every entry of a skill (hidden ones too) except its evals/, and leaves an evals/ folder that a
#      destination already had as it was (issue #8). The fresh install is also in step with the source file by
#      file, agents and commands included (scripts/install-status.sh, issue #6; skipped with a note if that
#      program is not next to this file)
#   5. install.sh has no default destination (static read of the file; the gate never runs it without one)
#   6. README.md lists every agent, command, skill and script (scripts/readme-listing-check.sh; a root without
#      README.md does not get this far since issue #29, check 0)
#   7. README.md carries no `git push` command whose target is main (issue #16; one FAIL per command line, with the
#      number of the line where the command starts; a quoted command counts too, the check cannot read a "never" in
#      front of it; a root without README.md does not get this far, check 0). Since issue #18 also: a command wrapped with a backslash, options
#      between git and push (git -C dir push ...), --all / --mirror / --branches, and a push without a ref after a
#      switch or checkout to main in the same code block. Since issue #30 also: git called by its path
#      (/usr/bin/git push ...), a ref or command in single quotes, and lines that end in a carriage return (CRLF).
#      Since issue #33 also: the command word in quotes ("git" push ..., "/usr/bin/git" push ...).
#      Since issue #32 also: a push without a ref after a switch or checkout to main in the same indented code block
#      (lines with four blanks or a tab in front, no fence; an empty line between them does not end the block).
#      Since issue #25 the same reader also runs over every file install.sh copies into a project: agents/*.md,
#      commands/*.md and every file of a skill (hidden ones and symlinked ones too) except its evals/. One FAIL per
#      command line there as well, named by the path of the file below the root. No exceptions file exists: the
#      readout of 2026-10-06 over the 18 installed files reported nothing (see the comment at the check)
# Usage:  scripts/gate.sh            # run from anywhere, also through a symlink; last line "gate: ok" (exit 0) or "gate: FAILED" (exit 1)
#          scripts/gate.sh --selftest # proves the checks fail on 24 broken fixtures and pass on 10 good ones (+ 29 line cases and 135 block cases for check 7,
#          + 10 starts of the gate file itself, directly and through symlinks, on a good and a broken tree - issue #29,
#          + 6 starts of install.sh, directly and through symlinks, each into a temp destination - issue #35, and 4 in a source without agents/, commands/ or skills/ - issue #45,
#          + 8 starts of the gate file with --push-main and 1 with --help - issue #25)
#          of these, one broken and one good fixture belong to check 3; they are skipped with a note if the store is absent
#          scripts/gate.sh --push-main [FILE ...]  # check 7 alone, as a readout (issue #25): one "FILE:LINE: command" line
#          per reported command, then the last line "push-main: ok files=N" (exit 0) or "push-main: FOUND hits=K files=N"
#          (exit 1); exit 2 and nothing read when a FILE is no readable file. Without FILE: the files check 7 reads in
#          this repo, README.md and what install.sh installs
#          scripts/gate.sh --help     # this header
set -uo pipefail

# Superseded header lines of the earlier state of this branch (PR #9, 4 broken + 2 good fixtures), kept as a comment
# when main was merged in. The header above is the valid one; these two lines are no usage text:
#   Usage:  scripts/gate.sh            # run from anywhere; last line "gate: ok" (exit 0) or "gate: FAILED" (exit 1)
#            scripts/gate.sh --selftest # proves the checks fail on 4 broken fixtures and pass on 2 good ones

# real_path FILE — absolute path of FILE with every symlink resolved (issue #29): a link to the file by readlink (a
# chain of at most 40 links, relative targets read from the link's own directory), a link in the directory part by
# cd -P. Only bash and readlink, so it does not depend on realpath or on readlink -f being there.
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

# issue #29: SELF is the program file itself, not the link the gate was started by - the root and the path of
# readme-listing-check.sh are derived from it
SELF="$(real_path "${BASH_SOURCE[0]}")" || { echo "gate.sh: cannot resolve its own path: ${BASH_SOURCE[0]}" >&2; echo "gate: FAILED"; exit 1; }
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
#     fence it lives for one line (since issue #32: or for one indented code block, see below). A switch or
#     checkout to another branch, a new branch or --detach clears it;
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
# Also reported since issue #33:
#   - the command word in quotes: "git" push, 'git' push, "/usr/bin/git" push (also a quoted path with a blank in
#     it, and /usr/bin/"git"). Quotes at the end of the command word are dropped before it is tested; what the word
#     has to be is unchanged ("legit", "my-git", "x/.git" are no command, and a quoted path or URL that ends in /git
#     matters only when the word after it, options aside, is push, switch or checkout)
# Also reported since issue #32:
#   - an indented code block (no fence): outside a fence the "main is checked out" state lives from one line to
#     the next while the lines are indented by four blanks, or by a tab after at most three blanks. An empty line
#     (nothing, or blanks and tabs only) between two indented lines belongs to the block and keeps the state, as in
#     CommonMark. The first line with text that is not indented that far ends it. The state has to be set inside
#     the indented lines: a switch to main in a line that is not indented lives for that line only, as before, so a
#     sentence that names the switch followed by an indented push is left alone.
#     Accepted limit: the check cannot tell an indented code block from the indented continuation paragraph of a
#     list item (CommonMark counts the indent from the list item's content; this check counts it from the start of
#     the line), so the state is also kept across indented prose and across a block that is nested deeper. That can
#     only report more, and only where a switch to main and a push without a ref really stand in indented lines
#     with nothing unindented between them. A fence line indented by four blanks is still read as a fence.
# Superseded by the block above (issue #32), kept as a comment - this stood at the head of "Still not seen":
#   an indented code block (four blanks or a tab, no fence) - a switch to main in one of its lines and a push
#   without a ref in the next are two lines outside a fence, so the state is gone (the fourth form of issue #30,
#   left out there on purpose because it changes how the state is scoped; now issue #32)
# Still not seen: git reached
# through a variable or a command substitution ("$GIT" push, ${GIT} push, $(command -v git) push,
# "$(command -v git)" push - left out of issue #33 on purpose: what a variable holds cannot be read from the text,
# and a rule for "any variable followed by push" would be a guess); the subcommand in quotes and quotes or a
# backslash inside the command word (git "push" origin main, gi"t" push, g\it push - issue #41; a backslash in
# front of the word, \git push, is seen); a file whose only line ends are bare carriage
# returns (one line for awk, named in issue #33, not built there); a branch change by other means
# (git switch --track origin/main,
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
      fence = 0; onmain = 0; found = 0; block = 0
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
        # Superseded by the three branches below (issue #32); the rule before, kept as a comment - outside a fence
        # the state was cleared at every line, so it never reached the second line of an indented code block:
        #   if (fence line) { fence = !fence; onmain = 0 }
        #   else if (!fence) onmain = 0
        # block = 1 while the lines read outside a fence are an indented code block: four blanks, or a tab after at
        # most three blanks, in front of the first physical line of the command. The state is kept from one such
        # line to the next and across an empty line (blanks and tabs only); it is cleared at the first indented
        # line after a line that was not (a switch to main in a line that is not indented lives for that line
        # only, as before) and at every line with text that is not indented that far.
        if (L[r] ~ /^[ \t]*(```|~~~)/) { fence = !fence; onmain = 0; block = 0 }
        else if (!fence) {
          if (L[r] ~ /^[ \t]*$/) { }
          else if (L[r] ~ /^(    | ? ? ?\t)/) { if (!block) onmain = 0; block = 1 }
          else { onmain = 0; block = 0 }
        }
        hit = 0
        for (i = 1; i < n && !hit; i++) {
          # the command word: git at the start of the word, after a character that is no part of a name ("git,
          # (git, `git), or after a slash (/usr/bin/git, ./git) - not legit, my-git, .git. Quotes at the end of
          # the word are dropped first (issue #33), so "git", \047git\047 and "/usr/bin/git" are read like git; a
          # quote in front of the word was no part of a name before. Only quotes: git) stays what it is.
          c = tok[i]; sub(/["\047]+$/, "", c)
          if (c !~ /(^|[^A-Za-z0-9_.\/-]|\/)git$/) continue
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

# tool_files ROOT — prints, each ended by a NUL byte and sorted by byte value, the path of every file install.sh
# copies from ROOT into a project (issue #25): agents/*.md, commands/*.md and every file of every skills/<name>/,
# hidden ones too, except the skill's own evals/ folder. The entries of a skill are taken the way install.sh takes
# them (three patterns, the entry named evals skipped), so an evals/ deeper inside a skill is read like install.sh
# installs it. Not printed: scripts/, .claude/ and README.md - they are not installed.
# A symlink to a file is printed by the path of the link, so its content is read: install.sh copies an agent or
# command with a plain cp, which copies what the link points to, and an entry of a skill with cp -r, which copies
# the link itself - on the machine of the install that link still leads to the same content. Not printed: a link
# that leads to no file, and what lies behind a link to a directory (cp -r copies that link, find does not enter
# it).
# Superseded first form of this function (same branch, before the symlink cases toolagentlink and toolskilllink):
# the agents and commands loop also tested [ ! -L "$f" ] and the skills loop ran find "$e" -type f -print0, so a
# linked file was never read and a command behind it passed check 7.
tool_files() {
  local root="$1" f d e
  {
    for f in "$root"/agents/*.md "$root"/commands/*.md; do
      [ -f "$f" ] && printf '%s\0' "$f"
    done
    for d in "$root"/skills/*/; do
      [ -d "$d" ] || continue
      for e in "$d"* "$d".[!.]* "$d"..?*; do
        [ -e "$e" ] || continue
        [ "$(basename "$e")" = "evals" ] && continue
        while IFS= read -r -d '' f; do
          [ -f "$f" ] && printf '%s\0' "$f"
        done < <(find "$e" \( -type f -o -type l \) -print0)
      done
    done
  } | LC_ALL=C sort -z
}

# push_main_readout [FILE...] — the option --push-main (issue #25): check 7 alone, as a readout. Runs
# readme_push_main over every FILE and prints one "FILE:LINE: command" line per report (FILE as it was given), then
# the last line "push-main: ok files=N" or "push-main: FOUND hits=K files=N". Returns 0 when nothing is reported, 1
# when something is, 2 when a FILE is no readable file - then nothing is read, so a readout never says ok about a
# list it read only in part.
# Without a FILE it reads what check 7 reads in the repo this file belongs to: README.md and the files of
# tool_files, named by their path below the repo root. Nothing to read there is exit 2 as well, not an ok.
push_main_readout() {
  local f out root="" strip="" hits=0 files=0
  local -a paths=()
  if [ "$#" -eq 0 ]; then
    root="$(cd -P "$(dirname "$SELF")/.." && pwd)" || { echo "gate.sh: --push-main: cannot resolve the repo root" >&2; return 2; }
    strip="$root/"
    [ -f "$root/README.md" ] && paths+=("$root/README.md")
    while IFS= read -r -d '' f; do paths+=("$f"); done < <(tool_files "$root")
    [ "${#paths[@]}" -gt 0 ] || { echo "gate.sh: --push-main: no README.md and no installed file in $root" >&2; return 2; }
  else
    paths=("$@")
  fi
  for f in "${paths[@]}"; do
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
      echo "gate.sh: --push-main: not a readable file: ${f#"$strip"}" >&2
      return 2
    fi
  done
  for f in "${paths[@]}"; do
    files=$((files + 1))
    while IFS= read -r out; do
      [ -n "$out" ] || continue
      printf '%s:%s\n' "${f#"$strip"}" "$out"
      hits=$((hits + 1))
    done < <(readme_push_main "$f")
  done
  if [ "$hits" -eq 0 ]; then
    echo "push-main: ok files=$files"
    return 0
  fi
  echo "push-main: FOUND hits=$hits files=$files"
  return 1
}

run_checks() {
  local root="$1" f
  FAILS=0

  # check 0 (issue #29): the root is a checkout of this repo. Without install.sh and README.md nearly every check
  # below is skipped or has nothing to read, so an empty directory - or the directory above a link to this file -
  # passed with nothing checked. Such a root is rejected here, and nothing in it is read or run.
  [ -f "$root/install.sh" ] || fail "not a checkout of this repo: no install.sh in $root"
  [ -f "$root/README.md" ] || fail "not a checkout of this repo: no README.md in $root"
  [ "$FAILS" -eq 0 ] || return 1

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
      # issue #6: counts alone do not prove content - the fresh install must be in step with the source file by
      # file, agents and commands included (the diff below reads skills/ only). install-status.sh is read from the
      # directory of this file; a gate file that stands alone says so instead of passing in silence.
      local stater
      stater="$(dirname "$SELF")/install-status.sh"
      if [ -f "$stater" ]; then
        if ! out="$(bash "$stater" --source "$root" "$tmp/dest" 2>&1)"; then
          fail "fresh install is not in step with the source (scripts/install-status.sh)"
          printf '%s\n' "$out"
        fi
      else
        echo "note: install-status skipped (no install-status.sh next to gate.sh)"
      fi
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
  # check 7, second part (issue #25): the same reader over every file install.sh copies into a project (tool_files:
  # agents/*.md, commands/*.md, every file of a skill except its evals/). An instruction there is repeated in every
  # session of the projects it is installed into - a wider reach than the README has. The FAIL line names the file
  # by its path below the root.
  # There is no exceptions file, on purpose: the readout over the tree of 2026-10-06 (scripts/gate.sh --push-main,
  # 18 installed files) reported nothing, so there is nothing to except. A command that is right in the repo it is
  # installed into (which push rule holds in hl_claw_bot is the open decision of issue #47) gets a declared
  # exception - a file with one line per exception and its reason, like scripts/skill-drift-declared.txt - when
  # the first one exists; until then such a command is reworded as a sentence or the gate stays red.
  while IFS= read -r -d '' f; do
    while IFS= read -r out; do
      [ -n "$out" ] || continue
      fail "${f#"$root"/}:${out%%:*}: git push to main in a file install.sh installs (issue #25: it is repeated in every session of the projects it is installed into):${out#*:}"
    done < <(readme_push_main "$f")
  done < <(tool_files "$root")
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

# fixture_readme FILE — writes the README of the selftest fixtures: it names agent a, command c, skill x and
# install.sh, so check 6 is green on the good fixture. 19 lines; the push cases append their block at line 20.
fixture_readme() {
  printf '# f\n\n```\nf/\n├── agents/\n│   └── a.md\n├── commands/\n│   └── c.md\n├── skills/\n│   └── x/\n└── install.sh\n```\n\n### `a`\n\n### `/c`\n\n### `/x`\n' > "$1"
}

# link_case WHAT DIR PATH WANT [TEXT] — selftest helper (issue #29): starts the gate file PATH with bash in the
# directory DIR. WANT is "<last output line> exit=N"; with TEXT the output must carry that text as well, which
# tells a rejection for the real root's reason from a rejection of some other root. Prints the difference and
# returns 1 when it does not hold.
link_case() {
  local out code got
  out="$(cd "$2" && bash "$3" 2>&1)"
  code=$?
  got="${out##*$'\n'} exit=$code"
  if [ "$got" != "$4" ]; then
    echo "selftest FAIL: $1: want '$4' got '$got'"
    return 1
  fi
  if [ -n "${5:-}" ] && ! printf '%s\n' "$out" | grep -q -F -- "$5"; then
    echo "selftest FAIL: $1: the output lacks '$5':"
    printf '%s\n' "$out"
    return 1
  fi
  return 0
}

# install_link_case WHAT DIR PATH DEST WANT — selftest helper (issue #35): starts the installer file PATH with bash
# in the directory DIR, with the destination DEST (a directory below the selftest's temp dir that does not exist
# yet). The start must end with exit 0, and DEST must then hold exactly the files WANT (one "./path" per line,
# sorted) - the files of the repo the installer file belongs to, not those of the directory above the link.
# Prints the difference and returns 1 when it does not hold.
install_link_case() {
  local out code got
  out="$(cd "$2" && bash "$3" "$4" 2>&1)"
  code=$?
  if [ "$code" -ne 0 ]; then
    echo "selftest FAIL: $1: exit $code, want 0; last line: ${out##*$'\n'}"
    return 1
  fi
  got="$(cd "$4" && find . -type f | LC_ALL=C sort)"
  if [ "$got" != "$5" ]; then
    echo "selftest FAIL: $1: installed files differ from those of the installer's own repo; got:"
    printf '    | %s\n' $got
    return 1
  fi
  return 0
}

# install_nosource_case WHAT DIR SRC DEST MISSING — selftest helper (issue #45): starts the installer file
# SRC/install.sh with bash in the directory DIR, with the destination DEST. SRC lacks the folders MISSING (as the
# installer names them, say "agents/, commands/, skills/"), and neither DEST nor the directory above it exists.
# Wanted: exit 1, exactly one line of output - the one that names SRC and MISSING and ends with
# "(nothing installed)" - and afterwards neither DEST nor the directory above it exists. Before issue #45 the
# installer made DEST/agents, DEST/commands and DEST/skills first and then stopped with a cp error on its source.
# Prints what differs and returns 1 when it does not hold.
install_nosource_case() {
  local out code src want bad=0
  src="$(cd -P "$3" && pwd)"
  want="install.sh: not a checkout of tgc-dev-tools: no $5 in $src (nothing installed)"
  out="$(cd "$2" && bash "$3/install.sh" "$4" 2>&1)"
  code=$?
  if [ "$code" -ne 1 ]; then
    echo "selftest FAIL: $1: exit $code, want 1"
    bad=1
  fi
  if [ "$out" != "$want" ]; then
    echo "selftest FAIL: $1: want the one line '$want', got:"
    printf '%s\n' "$out" | while IFS= read -r line; do printf '    | %s\n' "$line"; done
    bad=1
  fi
  if [ -e "$4" ] || [ -e "$(dirname "$4")" ]; then
    echo "selftest FAIL: $1: the destination exists after an install that failed; it holds:"
    find "$(dirname "$4")" | LC_ALL=C sort | while IFS= read -r line; do printf '    | %s\n' "$line"; done
    bad=1
  fi
  return "$bad"
}

# push_main_case WHAT DIR GATE WANT_EXIT WANT_OUT [ARG...] — selftest helper (issue #25): starts the gate file GATE
# with bash in the directory DIR as "GATE --push-main ARG...". The exit code must be WANT_EXIT and the whole output
# (stdout and stderr together) must be WANT_OUT, line for line. Prints both and returns 1 when it does not hold.
push_main_case() {
  local what="$1" dir="$2" gate="$3" wantcode="$4" want="$5" out code
  shift 5
  out="$(cd "$dir" && bash "$gate" --push-main "$@" 2>&1)"
  code=$?
  if [ "$code" -ne "$wantcode" ] || [ "$out" != "$want" ]; then
    echo "selftest FAIL: --push-main, $what: want exit $wantcode and"
    printf '%s\n' "$want" | sed 's/^/    | /'
    echo "  got exit $code and"
    printf '%s\n' "$out" | sed 's/^/    | /'
    return 1
  fi
  return 0
}

# tool_file_case WHAT ROOT WANT — selftest helper (check 7, issue #25): run_checks on the fixture ROOT must fail, and
# its FAIL lines must be exactly WANT - one line that names the file below ROOT, the line and the command. So the
# fixture is rejected by check 7 for that file and by nothing else. Prints the difference and returns 1 otherwise.
tool_file_case() {
  local out got
  if out="$(run_checks "$2" 2>&1)"; then
    echo "selftest FAIL: $1 accepted (issue #25)"
    return 1
  fi
  got="$(printf '%s\n' "$out" | grep '^FAIL: ')"
  if [ "$got" != "$3" ]; then
    echo "selftest FAIL: $1: want exactly this FAIL line"
    printf '%s\n' "$3" | sed 's/^/    | /'
    echo "  got"
    printf '%s\n' "$got" | sed 's/^/    | /'
    return 1
  fi
  return 0
}

selftest() {
  local t rc=0
  t="$(mktemp -d)"
  mkdir -p "$t/good/agents" "$t/good/commands" "$t/good/skills/x" "$t/bad/agents" "$t/bad/commands" "$t/bad/skills"
  printf -- '---\nname: a\ndescription: d\n---\nbody\n' > "$t/good/agents/a.md"
  printf 'cmd\n' > "$t/good/commands/c.md"
  printf -- '---\nname: x\ndescription: d\n---\nbody\n' > "$t/good/skills/x/SKILL.md"
  # empty / noinstall / noreadme (check 0, issue #29): a directory with nothing in it, the good fixture without
  # install.sh and the good fixture without README.md -> each rejected as "not a checkout of this repo", naming
  # exactly what is missing. Before issue #29 the first passed with nothing checked and the third was the good
  # fixture itself. noinstall and noreadme are copies of the good fixture taken while it is being put together.
  local out0
  mkdir -p "$t/empty"
  cp -r "$t/good" "$t/noinstall"
  fixture_readme "$t/noinstall/README.md"
  cp "$(dirname "$SELF")/../install.sh" "$t/good/install.sh"
  cp -r "$t/good" "$t/noreadme"
  fixture_readme "$t/good/README.md"
  out0="$(run_checks "$t/empty" 2>&1)" && { echo "selftest FAIL: empty directory accepted (issue #29)"; rc=1; }
  printf '%s\n' "$out0" | grep -q 'FAIL: not a checkout of this repo: no install.sh in ' || { echo "selftest FAIL: empty directory not rejected for the missing install.sh"; rc=1; }
  printf '%s\n' "$out0" | grep -q 'FAIL: not a checkout of this repo: no README.md in ' || { echo "selftest FAIL: empty directory not rejected for the missing README.md"; rc=1; }
  out0="$(run_checks "$t/noinstall" 2>&1)" && { echo "selftest FAIL: root without install.sh accepted (issue #29)"; rc=1; }
  [ "$out0" = "FAIL: not a checkout of this repo: no install.sh in $t/noinstall" ] || { echo "selftest FAIL: root without install.sh, want exactly the line for install.sh, got: $out0"; rc=1; }
  out0="$(run_checks "$t/noreadme" 2>&1)" && { echo "selftest FAIL: root without README.md accepted (issue #29)"; rc=1; }
  [ "$out0" = "FAIL: not a checkout of this repo: no README.md in $t/noreadme" ] || { echo "selftest FAIL: root without README.md, want exactly the line for README.md, got: $out0"; rc=1; }
  # bad: since check 0 it carries the README too, so it is still checks 1 and 2 that reject it - and they are named
  printf 'no frontmatter\n' > "$t/bad/agents/a.md"
  printf 'echo "unterminated\n' > "$t/bad/install.sh"
  fixture_readme "$t/bad/README.md"
  run_checks "$t/good" >/dev/null || { echo "selftest FAIL: good fixture rejected"; rc=1; }
  run_checks "$t/bad" >/dev/null && { echo "selftest FAIL: bad fixture accepted"; rc=1; }
  out0="$(run_checks "$t/bad" 2>&1)"
  printf '%s\n' "$out0" | grep -q -x 'FAIL: bash -n install.sh' || { echo "selftest FAIL: bad fixture not rejected by check 1 (bash -n install.sh)"; rc=1; }
  printf '%s\n' "$out0" | grep -q -x 'FAIL: frontmatter name/description: agents/a.md' || { echo "selftest FAIL: bad fixture not rejected by check 2 (frontmatter of agents/a.md)"; rc=1; }
  # default: good fixture whose install.sh carries a default destination again -> rejected (check 5)
  cp -r "$t/good" "$t/default"
  printf 'DEST="${1:-/nonexistent/.claude}"\n' >> "$t/default/install.sh"
  run_checks "$t/default" >/dev/null && { echo "selftest FAIL: default destination accepted"; rc=1; }
  # Superseded by the tamper block below (same fixture, and the reason for the rejection is asserted too); the older
  # assertion of this branch, kept as a comment when main was merged in:
  #   run_checks "$t/tamper" >/dev/null && { echo "selftest FAIL: altered install accepted"; rc=1; }
  # tamper: good fixture whose install.sh installs every file but alters one agent -> the counts match and the
  # skills are complete, the content is not what the source has -> rejected, and for that reason (check 4, issue #6)
  cp -r "$t/good" "$t/tamper"
  printf 'printf "altered\\n" >> "$DEST/agents/a.md"\n' >> "$t/tamper/install.sh"
  out0="$(run_checks "$t/tamper" 2>&1)" && { echo "selftest FAIL: altered install accepted"; rc=1; }
  printf '%s\n' "$out0" | grep -q -x 'FAIL: fresh install is not in step with the source (scripts/install-status.sh)' || { echo "selftest FAIL: tamper not rejected for the altered file"; rc=1; }
  printf '%s\n' "$out0" | grep -q -x 'DIFFERS  agents/a.md' || { echo "selftest FAIL: tamper output does not name the altered file"; rc=1; }
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
  # (since issue #29 the good fixture carries that README already - check 0 wants one; it is written again here so
  # that this case does not depend on it)
  cp -r "$t/good" "$t/listed"
  fixture_readme "$t/listed/README.md"
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
  # block cases for check 7 (issue #33), one more form.
  # form 8 — the command word in quotes ("git", 'git', "/usr/bin/git"): 10 reported, 13 left alone. The quotes at the
  # end of the command word are dropped before it is tested; the rule for the word itself is the one of form 5 (git,
  # or a path that ends in /git - not legit, my-git, .git), and a quoted path or URL that ends in /git matters only
  # when the word after it (options aside) is push, switch or checkout.
  push_block 1 '"/usr/bin/git" push origin main' || rc=1
  push_block 1 '"git" push origin main' || rc=1
  push_block 1 "'git' push origin main" || rc=1
  push_block 1 "'/usr/bin/git' push -u origin HEAD:main" || rc=1
  push_block 1 '"git" -C ../x push origin main' || rc=1
  push_block 1 '("/usr/bin/git" push origin main)' || rc=1
  push_block 1 'Then run `"git" push --all`.' || rc=1
  push_block 1 '"/opt/my tools/git" push origin main' || rc=1
  push_block 1 '/usr/bin/"git" push origin main' || rc=1
  push_block 3 "$F" '"git" switch main' '"git" push' "$F" || rc=1
  push_block '' '"/usr/bin/git" push -u origin feat/x' || rc=1
  push_block '' '"git" push origin feat/x' || rc=1
  push_block '' "'git' pull origin main" || rc=1
  push_block '' '"legit" push origin main' || rc=1
  push_block '' '"my-git" push origin main' || rc=1
  push_block '' '"x/.git" push origin main' || rc=1
  push_block '' 'git clone "https://example.org/git" main' || rc=1
  push_block '' 'git -C "../git" push origin feat/x' || rc=1
  push_block '' 'echo "git" && git push -u origin feat/x' || rc=1
  push_block '' "$F" '"git" switch main' '"git" switch feat/x' '"git" push' "$F" || rc=1
  # the last three are not left alone because they are harmless: they are the forms the check cannot read (named
  # under "Still not seen" above readme_push_main). A variable cannot be resolved from the text, and the quote that
  # closes "$(...)" is dropped while the bracket in front of it stays, so the word is still no git.
  push_block '' '"$GIT" push origin main' || rc=1
  push_block '' '$(command -v git) push origin main' || rc=1
  push_block '' '"$(command -v git)" push origin main' || rc=1
  # block cases for check 7 (issue #32), one more form. T is a tab.
  # form 9 — a push without a ref while main is checked out, in an indented code block (four blanks or a tab in
  # front of the line, no fence): 12 reported, 14 left alone. Outside a fence the state lives from one indented line
  # to the next; an empty line between two indented lines belongs to the block and keeps it; the first line with
  # text that is not indented that far ends it. The state has to be set inside the indented lines: a switch to main
  # in a line that is not indented lives for that line only, as before.
  local T=$'\t'
  push_block 2 '    git switch main' '    git push' || rc=1
  push_block 4 'An indented block:' '' '    git switch main' '    git push' || rc=1
  push_block 2 "${T}git switch main" "${T}git push" || rc=1
  push_block 2 "  ${T}git switch main" "  ${T}git push origin" || rc=1
  push_block 3 '    git switch main' '' '    git push' || rc=1
  push_block 3 '    git switch main' '  ' '    git push' || rc=1
  push_block 3 '    git checkout main' '    git pull --ff-only origin main' '    git push origin' || rc=1
  push_block 2 '    git switch main' '    git push -u origin HEAD' || rc=1
  push_block 2 '        git switch main' '        git push' || rc=1
  push_block '2 3' '    git switch main' '    git push' "${T}git push origin" || rc=1
  push_block 3 '    git switch main && \' '      git pull --ff-only origin main' '    git push' || rc=1
  push_block 3 "    git switch main$R" "$R" "    git push$R" || rc=1
  push_block '' '    git switch main' 'Then, on the work branch:' '    git push' || rc=1
  push_block '' '    git switch main' '' 'Then, on the work branch:' '' '    git push' || rc=1
  push_block '' '    git switch main' '    git pull --ff-only origin main' || rc=1
  push_block '' '    git switch main' '    git push -u origin feat/x' || rc=1
  push_block '' '    git switch main' '    git push origin --tags' || rc=1
  push_block '' '    git switch main' '    git switch feat/x' '    git push' || rc=1
  push_block '' '    git switch main' '    git switch -c feat/x' '    git push' || rc=1
  push_block '' '    git add README.md' '    git push' || rc=1
  push_block '' '    git switch main' 'git push' || rc=1
  push_block '' 'Run `git switch main` first.' '' '    git push' || rc=1
  push_block '' 'git switch main' '    git push' || rc=1
  push_block '' '   git switch main' '   git push' || rc=1
  push_block '' '    git switch main' "$F" 'git push' "$F" || rc=1
  push_block '' "$F" 'git switch main' "$F" '    git push' || rc=1
  # block cases for check 7 (issue #41), one more form.
  # form 10 — the subcommand in quotes (git "push", git 'switch', git "checkout"): 13 reported, 15 left alone. A word
  # that is push, switch or checkout between one pair of quotes is that subcommand and the words after it are its
  # arguments; closing punctuation behind the pair ends the command at the word, as it does behind the bare word.
  push_block 1 'git "push" origin main' || rc=1
  push_block 1 "git 'push' origin main" || rc=1
  push_block 1 'git "push" origin "main"' || rc=1
  push_block 1 'git -C ../x "push" -u origin HEAD:main' || rc=1
  push_block 1 "\"git\" 'push' --all" || rc=1
  push_block 1 'Then run `git "push" origin main`.' || rc=1
  push_block 1 "sh -c \"git 'push' origin main\"" || rc=1
  push_block 3 "$F" 'git "switch" main' 'git push' "$F" || rc=1
  push_block 3 "$F" "git 'checkout' main" 'git push origin' "$F" || rc=1
  push_block 3 "$F" 'git switch main' 'git "push"' "$F" || rc=1
  push_block 2 '    git "switch" main' "    git 'push'" || rc=1
  push_block 1 "sh -c 'git switch main && git \"push\"'" || rc=1
  # the thirteenth was reported before issue #41 too. It is here because the new rule must not change it: the quote
  # behind push closes the whole command, so the words after it are arguments of sh, not a remote and a ref - the
  # push carries no ref and main is checked out.
  push_block 3 "$F" 'git switch main' "sh -c 'git push' origin feat/x" "$F" || rc=1
  push_block '' 'git "push" origin feature' || rc=1
  push_block '' "git 'push' -u origin 'feat/x'" || rc=1
  push_block '' 'git "push" origin main:feat/x' || rc=1
  push_block '' 'git "status"' || rc=1
  push_block '' 'git "pull" origin main' || rc=1
  # the quote closes the whole command (no quote in front of push): the command ends at the word, as before
  push_block '' "sh -c 'git push' origin main" || rc=1
  # one quoted word for git, and a quote that is not closed by its own kind: neither is a pair around push
  push_block '' "git 'push origin main'" || rc=1
  push_block '' "git \"push' origin main" || rc=1
  # a quoted switch to another branch clears the state. Before issue #41 it was not read, the state stayed on main
  # and the push in the first of these four was reported at line 4 - a report for a push of feat/x.
  push_block '' "$F" 'git switch main' 'git "switch" feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git "switch" main' "git 'switch' -c feat/x" 'git push' "$F" || rc=1
  push_block '' "$F" 'git "checkout" feat/x' 'git push' "$F" || rc=1
  push_block '' "$F" 'git "switch" main' 'git push -u origin feat/x' "$F" || rc=1
  push_block '' "sh -c 'git switch feat/x && git \"push\"'" || rc=1
  # the last two are not left alone because they are harmless: they are the second form of issue #41, quotes or a
  # backslash inside the command word, which was decided not to be built (named under "Still not seen" above
  # readme_push_main with the reason). The shell runs both as git push origin main.
  push_block '' 'gi"t" push origin main' || rc=1
  push_block '' 'g\it push origin main' || rc=1
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
  # pushindent / pushindentflow (issue #32): the listed README plus an indented code block (no fence). The appended
  # text is an empty line (19), a sentence (20), an empty line (21) and the two command lines (22, 23) - the fixture
  # of the issue. The push without a ref is named at its own line (23); the same block with a switch to main, a pull
  # and the install (step 3 of the real README, written as an indented block) stays accepted.
  cp -r "$t/listed" "$t/pushindent"
  printf '\nAn indented block:\n\n    git switch main\n    git push\n' >> "$t/pushindent/README.md"
  out="$(run_checks "$t/pushindent")"
  case "$out" in
    *"FAIL: README.md:23: git push to main"*) ;;
    *) echo "selftest FAIL: README with 'git switch main' + 'git push' in an indented code block accepted"; rc=1 ;;
  esac
  cp -r "$t/listed" "$t/pushindentflow"
  printf '\nAn indented block:\n\n    git switch main && git pull --ff-only origin main\n    ./install.sh /tmp/x/.claude\n' >> "$t/pushindentflow/README.md"
  out="$(run_checks "$t/pushindentflow")" || {
    echo "selftest FAIL: README with 'git switch main && git pull' + install in an indented code block rejected:"
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
  # tool file cases (check 7, issue #25): the listed fixture (checks 1 to 6 green, README without a push) plus a push
  # instruction in a file that install.sh copies into a project - there it is repeated in every session. 7 rejected
  # (one per kind of installed file, and two that are reached through a symlink), each by exactly one FAIL line
  # that names the file, the line and the command; 2 accepted. The fixture files: agents/a.md and skills/x/SKILL.md have 5 lines, commands/c.md has 1; an appended
  # block starts with a blank line.
  #   toolagent:     agents/a.md + a code block                      -> the command is line 8
  #   toolcommand:   commands/c.md + a sentence with inline code     -> line 3
  #   toolskill:     skills/x/SKILL.md + a block that switches to main and pushes without a ref -> the push, line 9
  #   toolskillfile: a new file skills/x/references/flow.md          -> line 3
  #   toolhidden:    a new hidden file skills/x/.notes.md            -> line 1
  #   toolevals:     the same command in skills/x/evals/e.md, which install.sh does not install -> accepted
  #   toolbranch:    agents/a.md + a push of a branch, main in prose -> accepted
  local why25='git push to main in a file install.sh installs (issue #25: it is repeated in every session of the projects it is installed into)'
  cp -r "$t/listed" "$t/toolagent"
  printf '\n```bash\ngit push origin main\n```\n' >> "$t/toolagent/agents/a.md"
  tool_file_case "agent file with 'git push origin main'" "$t/toolagent" "FAIL: agents/a.md:8: $why25: git push origin main" || rc=1
  cp -r "$t/listed" "$t/toolcommand"
  printf '\nThen run `git push origin HEAD:main`.\n' >> "$t/toolcommand/commands/c.md"
  tool_file_case "command file with 'git push origin HEAD:main' as inline code" "$t/toolcommand" "FAIL: commands/c.md:3: $why25: Then run \`git push origin HEAD:main\`." || rc=1
  cp -r "$t/listed" "$t/toolskill"
  printf '\n```bash\ngit switch main\ngit push\n```\n' >> "$t/toolskill/skills/x/SKILL.md"
  tool_file_case "SKILL.md with 'git switch main' + 'git push' in one block" "$t/toolskill" "FAIL: skills/x/SKILL.md:9: $why25: git push" || rc=1
  cp -r "$t/listed" "$t/toolskillfile"
  mkdir -p "$t/toolskillfile/skills/x/references"
  printf '# flow\n\ngit push --all\n' > "$t/toolskillfile/skills/x/references/flow.md"
  tool_file_case "file in a folder of a skill with 'git push --all'" "$t/toolskillfile" "FAIL: skills/x/references/flow.md:3: $why25: git push --all" || rc=1
  cp -r "$t/listed" "$t/toolhidden"
  printf 'git push -u origin feat/x:main\n' > "$t/toolhidden/skills/x/.notes.md"
  tool_file_case "hidden file of a skill with 'git push -u origin feat/x:main'" "$t/toolhidden" "FAIL: skills/x/.notes.md:1: $why25: git push -u origin feat/x:main" || rc=1
  #   toolagentlink: agents/a.md is a symlink to shared/a.md, a file outside agents/ that carries the command.
  #                  install.sh copies agents and commands with a plain cp, which copies what a link points to, so
  #                  the content reaches the project -> rejected, named by the path of the link, line 8
  #   toolskilllink: skills/x/more.md is a symlink (absolute target) to a file outside the skill that carries the
  #                  command. install.sh copies the entries of a skill with cp -r, which copies the link itself; on
  #                  the machine of the install the link still leads to that content -> rejected, line 1
  cp -r "$t/listed" "$t/toolagentlink"
  mkdir -p "$t/toolagentlink/shared"
  mv "$t/toolagentlink/agents/a.md" "$t/toolagentlink/shared/a.md"
  printf '\n```bash\ngit push origin main\n```\n' >> "$t/toolagentlink/shared/a.md"
  ln -s ../shared/a.md "$t/toolagentlink/agents/a.md"
  tool_file_case "agent file that is a symlink to a file with 'git push origin main'" "$t/toolagentlink" "FAIL: agents/a.md:8: $why25: git push origin main" || rc=1
  cp -r "$t/listed" "$t/toolskilllink"
  mkdir -p "$t/toolskilllink/shared"
  printf 'git push origin main\n' > "$t/toolskilllink/shared/more.md"
  ln -s "$t/toolskilllink/shared/more.md" "$t/toolskilllink/skills/x/more.md"
  tool_file_case "symlink inside a skill to a file with 'git push origin main'" "$t/toolskilllink" "FAIL: skills/x/more.md:1: $why25: git push origin main" || rc=1
  cp -r "$t/listed" "$t/toolevals"
  mkdir -p "$t/toolevals/skills/x/evals"
  printf 'git push origin main\n' > "$t/toolevals/skills/x/evals/e.md"
  out="$(run_checks "$t/toolevals" 2>&1)" || {
    echo "selftest FAIL: 'git push origin main' in a skill's evals/ (not installed) rejected:"
    printf '%s\n' "$out"
    rc=1
  }
  cp -r "$t/listed" "$t/toolbranch"
  printf '\nThe change reaches `main` through a pull request, never by a push to `main`:\n\n```bash\ngit push -u origin feat/x\n```\n' >> "$t/toolbranch/agents/a.md"
  out="$(run_checks "$t/toolbranch" 2>&1)" || {
    echo "selftest FAIL: agent file with 'git push -u origin feat/x' rejected:"
    printf '%s\n' "$out"
    rc=1
  }
  # option cases (issue #25): the gate file itself, started with --push-main - check 7 alone, as a readout. One
  # "FILE:LINE: command" line per report, then a last line with the counts; exit 0 nothing reported, 1 reported,
  # 2 a FILE that is no readable file (nothing is read then). The whole output is compared, line for line.
  #   pm/hit.md:   a push to main at line 3
  #   pm/two.md:   one at line 1 and a wrapped one that starts at line 5
  #   pm/clean.md: a push of a branch, and main in prose only
  #   pm/sub/:     a directory - no file; also the empty directory the starts without a FILE are made in
  #   pmrepo / pmrepobad: the good fixture plus scripts/ with a copy of this file, for the start without a FILE. It
  #                reads README.md and what install.sh installs from the repo the gate file belongs to, wherever it
  #                is started. pmrepobad carries a push to main in skills/x/references/flow.md (installed, so it is
  #                reported) and in skills/x/evals/e.md (not installed, so it is not read and not counted)
  # 8 starts with --push-main: 3 with files that can be read (one with a report, one without, three files in one
  # start), 3 with a FILE that is none (missing, missing next to one with a report, a directory), 2 without a FILE
  # (pmrepo, pmrepobad). Then 1 start with --help: exit 0, the header from its first line on, the option named in it.
  local helpout
  mkdir -p "$t/pm/sub"
  printf '# f\n\ngit push origin main\n' > "$t/pm/hit.md"
  printf 'git push origin HEAD:main\n\n```bash\ngit fetch origin\ngit push -u origin \\\n  main\n```\n' > "$t/pm/two.md"
  printf 'The change reaches `main` through a pull request, never by a push to `main`:\n\n```bash\ngit push -u origin feat/x\n```\n' > "$t/pm/clean.md"
  push_main_case "one file with a push to main" "$t/pm" "$SELF" 1 \
    $'hit.md:3: git push origin main\npush-main: FOUND hits=1 files=1' hit.md || rc=1
  push_main_case "one file without one" "$t/pm" "$SELF" 0 'push-main: ok files=1' clean.md || rc=1
  push_main_case "three files, three reports in two of them" "$t/pm" "$SELF" 1 \
    $'hit.md:3: git push origin main\ntwo.md:1: git push origin HEAD:main\ntwo.md:5: git push -u origin main\npush-main: FOUND hits=3 files=3' clean.md hit.md two.md || rc=1
  push_main_case "a FILE that does not exist" "$t/pm" "$SELF" 2 'gate.sh: --push-main: not a readable file: nope.md' nope.md || rc=1
  push_main_case "a FILE that does not exist next to one with a report" "$t/pm" "$SELF" 2 \
    'gate.sh: --push-main: not a readable file: nope.md' hit.md nope.md || rc=1
  push_main_case "a directory as FILE" "$t/pm" "$SELF" 2 'gate.sh: --push-main: not a readable file: sub' sub || rc=1
  cp -r "$t/good" "$t/pmrepo"
  mkdir -p "$t/pmrepo/scripts"
  cp "$SELF" "$t/pmrepo/scripts/gate.sh"
  cp -r "$t/pmrepo" "$t/pmrepobad"
  mkdir -p "$t/pmrepobad/skills/x/references" "$t/pmrepobad/skills/x/evals"
  printf '# flow\n\ngit push origin main\n' > "$t/pmrepobad/skills/x/references/flow.md"
  printf 'git push origin main\n' > "$t/pmrepobad/skills/x/evals/e.md"
  push_main_case "no FILE, a repo without a push to main" "$t/pm/sub" "$t/pmrepo/scripts/gate.sh" 0 'push-main: ok files=4' || rc=1
  push_main_case "no FILE, a repo with one in an installed skill file and one in evals/" "$t/pm/sub" "$t/pmrepobad/scripts/gate.sh" 1 \
    $'skills/x/references/flow.md:3: git push origin main\npush-main: FOUND hits=1 files=5' || rc=1
  helpout="$(cd "$t/pm/sub" && bash "$SELF" --help 2>&1)" || { echo "selftest FAIL: --help does not end with exit 0"; rc=1; }
  [ "${helpout%%$'\n'*}" = "gate.sh — offline gate for tgc-dev-tools (fleet board gate, routing[\"gates\"])." ] || {
    echo "selftest FAIL: --help does not start with the first line of the header, but with: ${helpout%%$'\n'*}"; rc=1; }
  printf '%s\n' "$helpout" | grep -q -F -- 'scripts/gate.sh --push-main [FILE ...]' || { echo "selftest FAIL: --help does not name --push-main [FILE ...]"; rc=1; }
  # link cases (issue #29): the gate file itself, started with bash in an empty directory, directly and through
  # symlinks - the last line and the exit code are those of the repo the file belongs to, never of the directory
  # above the link.
  #   linkrepo / linkrepobad: the good fixture plus scripts/ with a copy of this file and of readme-listing-check.sh;
  #                           linkrepobad has an agent without frontmatter (check 2 red)
  #   overgood / overbad:     a passing and a failing tree WITHOUT scripts/ - the directories the links are put into.
  #                           A gate that takes the directory above the link reads these instead: green on the
  #                           link to linkrepobad, red on the link to linkrepo
  # 10 starts: 2 direct, 2 through a file link in an otherwise empty directory (the measured case of the issue), 2
  # through a file link inside overgood / overbad, 1 through a link with a relative target, 1 through a link to a
  # link, 2 through a link to the scripts/ directory. Every rejected start must name the agent of linkrepobad.
  local why='FAIL: frontmatter name/description: agents/a.md'
  cp -r "$t/good" "$t/linkrepo"
  mkdir -p "$t/linkrepo/scripts"
  cp "$SELF" "$t/linkrepo/scripts/gate.sh"
  cp "$(dirname "$SELF")/readme-listing-check.sh" "$t/linkrepo/scripts/readme-listing-check.sh"
  printf '\nGate: `scripts/gate.sh` with `scripts/readme-listing-check.sh`\n' >> "$t/linkrepo/README.md"
  cp -r "$t/linkrepo" "$t/linkrepobad"
  printf 'no frontmatter\n' > "$t/linkrepobad/agents/a.md"
  cp -r "$t/good" "$t/overgood"
  cp -r "$t/good" "$t/overbad"
  printf 'no frontmatter\n' > "$t/overbad/agents/a.md"
  mkdir -p "$t/cwd" "$t/lone/sub" "$t/overgood/sub" "$t/overbad/sub" "$t/rel/sub" "$t/chain/sub"
  ln -s "$t/linkrepo/scripts/gate.sh" "$t/lone/sub/gate.sh"
  ln -s "$t/linkrepobad/scripts/gate.sh" "$t/lone/sub/gate-bad.sh"
  ln -s "$t/linkrepobad/scripts/gate.sh" "$t/overgood/sub/gate.sh"
  ln -s "$t/linkrepo/scripts/gate.sh" "$t/overbad/sub/gate.sh"
  ln -s ../../linkrepobad/scripts/gate.sh "$t/rel/sub/gate.sh"
  ln -s "$t/rel/sub/gate.sh" "$t/chain/sub/gate.sh"
  ln -s "$t/linkrepobad/scripts" "$t/overgood/scripts"
  ln -s "$t/linkrepo/scripts" "$t/overbad/scripts"
  link_case "direct start, good tree" "$t/cwd" "$t/linkrepo/scripts/gate.sh" 'gate: ok exit=0' || rc=1
  link_case "direct start, broken tree" "$t/cwd" "$t/linkrepobad/scripts/gate.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "file link in an empty directory, good tree" "$t/cwd" "$t/lone/sub/gate.sh" 'gate: ok exit=0' || rc=1
  link_case "file link in an empty directory, broken tree" "$t/cwd" "$t/lone/sub/gate-bad.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "file link to the broken tree, placed inside a passing tree" "$t/cwd" "$t/overgood/sub/gate.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "file link to the good tree, placed inside a failing tree" "$t/cwd" "$t/overbad/sub/gate.sh" 'gate: ok exit=0' || rc=1
  link_case "file link with a relative target, broken tree" "$t/cwd" "$t/rel/sub/gate.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "link to a link, broken tree" "$t/cwd" "$t/chain/sub/gate.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "link to scripts/ of the broken tree, placed inside a passing tree" "$t/cwd" "$t/overgood/scripts/gate.sh" 'gate: FAILED exit=1' "$why" || rc=1
  link_case "link to scripts/ of the good tree, placed inside a failing tree" "$t/cwd" "$t/overbad/scripts/gate.sh" 'gate: ok exit=0' || rc=1
  # installer link cases (issue #35): install.sh of this repo as linkrepo carries it (agent a, command c, skill x),
  # started with bash in an empty directory, directly and through symlinks, each time into a destination of its
  # own below the temp dir. Every start ends with exit 0 and installs exactly the three files of linkrepo.
  #   instdecoy: a directory with agents/, commands/ and skills/ of its own (one file "decoy" in each) - where one
  #              link is put. An installer that takes the directory of the link installs the decoy files from
  #              there and ends with exit 0; from an empty directory it stops with a cp error (the measured case).
  # 6 starts: 1 direct, 1 through a file link in an otherwise empty directory, 1 through a file link inside
  # instdecoy, 1 through a link with a relative target, 1 through a link to a link, 1 through a link to the repo
  # directory.
  local inst=$'./agents/a.md\n./commands/c.md\n./skills/x/SKILL.md'
  mkdir -p "$t/instdecoy/agents" "$t/instdecoy/commands" "$t/instdecoy/skills/decoy" "$t/instdir" "$t/instdest"
  printf -- '---\nname: decoy\ndescription: d\n---\nbody\n' > "$t/instdecoy/agents/decoy.md"
  printf 'cmd\n' > "$t/instdecoy/commands/decoy.md"
  printf -- '---\nname: decoy\ndescription: d\n---\nbody\n' > "$t/instdecoy/skills/decoy/SKILL.md"
  ln -s "$t/linkrepo/install.sh" "$t/lone/sub/install.sh"
  ln -s "$t/linkrepo/install.sh" "$t/instdecoy/install.sh"
  ln -s ../../linkrepo/install.sh "$t/rel/sub/install.sh"
  ln -s "$t/rel/sub/install.sh" "$t/chain/sub/install.sh"
  ln -s "$t/linkrepo" "$t/instdir/repo"
  install_link_case "installer, direct start" "$t/cwd" "$t/linkrepo/install.sh" "$t/instdest/direct/.claude" "$inst" || rc=1
  install_link_case "installer, file link in an empty directory" "$t/cwd" "$t/lone/sub/install.sh" "$t/instdest/lone/.claude" "$inst" || rc=1
  install_link_case "installer, file link placed in a directory with agents/, commands/, skills/ of its own" "$t/cwd" "$t/instdecoy/install.sh" "$t/instdest/decoy/.claude" "$inst" || rc=1
  install_link_case "installer, file link with a relative target" "$t/cwd" "$t/rel/sub/install.sh" "$t/instdest/rel/.claude" "$inst" || rc=1
  install_link_case "installer, link to a link" "$t/cwd" "$t/chain/sub/install.sh" "$t/instdest/chain/.claude" "$inst" || rc=1
  install_link_case "installer, link to the repo directory" "$t/cwd" "$t/instdir/repo/install.sh" "$t/instdest/dir/.claude" "$inst" || rc=1
  # installer source cases (issue #45): install.sh of this repo in a directory that is not a checkout of it,
  # started with bash in an empty directory, each time with a destination below the temp dir that does not exist.
  # Every start ends with exit 1 and one line that names the source and what it lacks, and the destination still
  # does not exist afterwards (before, the installer had already made agents/, commands/ and skills/ in it).
  #   nosrc/none:     a copy of install.sh alone in a directory - the measured case of the issue
  #   nosrc/agents:   the good fixture's commands/ and skills/ beside it, no agents/
  #   nosrc/commands: the good fixture's agents/ and skills/ beside it, no commands/ (before, a.md was installed
  #                   and then the install stopped)
  #   nosrc/skills:   the good fixture's agents/ and commands/ beside it, no skills/
  # 4 starts: 1 with none of the three folders, 3 with exactly one of them missing.
  local srcinst miss keep
  srcinst="$(dirname "$SELF")/../install.sh"
  mkdir -p "$t/nosrc/none"
  cp "$srcinst" "$t/nosrc/none/install.sh"
  install_nosource_case "installer alone in a directory" "$t/cwd" "$t/nosrc/none" "$t/nosrcdest/none/.claude" "agents/, commands/, skills/" || rc=1
  for miss in agents commands skills; do
    mkdir -p "$t/nosrc/$miss"
    cp "$srcinst" "$t/nosrc/$miss/install.sh"
    for keep in agents commands skills; do
      [ "$keep" = "$miss" ] || cp -r "$t/good/$keep" "$t/nosrc/$miss/$keep"
    done
    install_nosource_case "installer in a source without $miss/" "$t/cwd" "$t/nosrc/$miss" "$t/nosrcdest/$miss/.claude" "$miss/" || rc=1
  done
  rm -rf "$t"
  [ "$rc" -eq 0 ] && echo "selftest ok"
  return "$rc"
}

if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
# issue #25: the header of this file as the usage text, and check 7 alone as a readout
case "${1:-}" in
  -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$SELF"; exit 0 ;;
  --push-main) shift; push_main_readout "$@"; exit $? ;;
esac
# issue #29: SELF is resolved, so this is the repo the program file belongs to, however the gate was started
ROOT="$(cd -P "$(dirname "$SELF")/.." && pwd)"
if run_checks "$ROOT"; then echo "gate: ok"; else echo "gate: FAILED"; exit 1; fi
