#!/usr/bin/env bash
# branch-after-probe.sh — which branch does a git command leave checked out, and where would a push go then?
#
# What it does: runs each COMMAND with the real git in a throwaway clone and prints what is true afterwards. It is
# the measurement behind check 7 of scripts/gate.sh (issue #24): that check reads the words of a command and decides
# "main is checked out from here on"; this program asks git itself. Since issue #75 the selftest also holds how git
# reads the options of switch / checkout (a value as its own word, short options in one word, a glued name).
# Every COMMAND gets a fresh clone of a fresh bare remote "origin" with the branches main, feature, maintenance and
# topic/main. Before the COMMAND the clone stands on the local branch work (made from origin/feature, no upstream)
# and has no local branch main. Nothing outside the temp directory is read or written: the user's and the system's
# git configuration are switched off (so push.default is git's own default, simple), and the pushes are dry runs.
# Usage:   scripts/branch-after-probe.sh 'COMMAND' ['COMMAND' ...]   # a COMMAND is a git command line without the word
#                                                                   # git; several steps are joined with " ; "
#          scripts/branch-after-probe.sh 'switch --track origin/main' 'switch main ; branch -m trunk'
#          scripts/branch-after-probe.sh --selftest                  # 58 commands against the answers written down here
#          scripts/branch-after-probe.sh --help                      # this header
# Output:  one line per COMMAND "branch=B push=P push-head=H exit=N | COMMAND", then the last line
#          "branch-after: commands=N on-main=K"
#            branch     the branch checked out after the COMMAND ("detached" when HEAD is on no branch)
#            push       the remote branch a `git push` without a ref would update ("refused" when git does not push)
#            push-head  the remote branch a `git push origin HEAD` would update ("refused" as above)
#            exit       0, or the exit code of the first step of the COMMAND that failed (the steps behind it still run)
#            on-main    how many COMMANDs left the branch main checked out
# Exit:    0 the readout was made (whatever it says) · 1 the selftest found a difference · 2 usage, or no git
set -uo pipefail

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }

# g ARG ... — git without the user's and the system's configuration, with a fixed identity and no prompt. A
# GIT_DIR or GIT_WORK_TREE of the calling shell is dropped, so every call needs its own -C DIR.
g() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
    GIT_AUTHOR_NAME=probe GIT_AUTHOR_EMAIL=probe@example.invalid \
    GIT_COMMITTER_NAME=probe GIT_COMMITTER_EMAIL=probe@example.invalid \
    git "$@"
}

# make_clone DIR — DIR/origin.git (bare: main, feature, maintenance, topic/main) and DIR/clone, standing on the
# local branch work with no upstream and without a local branch main. Returns 1 when git could not build it.
make_clone() {
  local d="$1"
  g init -q -b main "$d/seed" || return 1
  g -C "$d/seed" commit -q --allow-empty -m one || return 1
  g -C "$d/seed" branch feature || return 1
  g -C "$d/seed" branch maintenance || return 1
  g -C "$d/seed" branch topic/main || return 1
  g clone -q --bare "$d/seed" "$d/origin.git" || return 1
  g clone -q "$d/origin.git" "$d/clone" 2>/dev/null || return 1
  g -C "$d/clone" switch -q -c work --no-track origin/feature || return 1
  g -C "$d/clone" branch -q -D main || return 1
}

# push_target DIR [ARG ...] — the remote branch a dry-run push with the ARGs would update, or "refused". Read from
# the --porcelain lines "<flag> TAB <from>:<to> TAB <note>"; the first one counts.
push_target() {
  local d="$1" flag refs note to="refused"
  shift
  while IFS=$'\t' read -r flag refs note; do
    case "$refs" in
      *:refs/heads/*) to="${refs##*:refs/heads/}"; break ;;
    esac
  done < <(g -C "$d" push --dry-run --porcelain "$@" 2>/dev/null)
  printf '%s\n' "$to"
}

# probe_one COMMAND — prints "branch=B push=P push-head=H exit=N"; returns 1 when the clone could not be built
probe_one() {
  local t rc=0 step code branch steps=() words=()
  t="$(mktemp -d)"
  if ! make_clone "$t" >/dev/null 2>&1; then
    rm -rf "$t"
    return 1
  fi
  # the steps of the COMMAND, split at " ; "; the words of a step are split at blanks, no quoting inside a step
  IFS=';' read -ra steps <<< "$1"
  for step in "${steps[@]}"; do
    read -ra words <<< "$step"
    [ "${#words[@]}" -gt 0 ] || continue
    g -C "$t/clone" "${words[@]}" >/dev/null 2>&1
    code=$?
    [ "$rc" -eq 0 ] && rc=$code
  done
  branch="$(g -C "$t/clone" symbolic-ref --short -q HEAD)" || branch="detached"
  printf 'branch=%s push=%s push-head=%s exit=%s\n' \
    "$branch" "$(push_target "$t/clone")" "$(push_target "$t/clone" origin HEAD)" "$rc"
  rm -rf "$t"
}

# probe COMMAND ... — the lines described under Output
probe() {
  local c res n=0 onmain=0
  for c in "$@"; do
    res="$(probe_one "$c")" || { echo "branch-after-probe.sh: git could not build the throwaway clone" >&2; return 2; }
    printf '%s | %s\n' "$res" "$c"
    n=$((n + 1))
    case "$res" in "branch=main "*) onmain=$((onmain + 1)) ;; esac
  done
  echo "branch-after: commands=$n on-main=$onmain"
}

# want WANT COMMAND — selftest helper: WANT is "B P H N" (branch, push, push-head, exit; N may be "any" for a
# command git rejects, where only the state it leaves is the claim). Prints the difference and returns 1.
want() {
  local w="$1" c="$2" res b p h n wb wp wh wn
  res="$(probe_one "$c")" || { echo "selftest FAIL: no throwaway clone for: $c"; return 1; }
  read -r b p h n <<< "$res"
  read -r wb wp wh wn <<< "$w"
  b="${b#branch=}"; p="${p#push=}"; h="${h#push-head=}"; n="${n#exit=}"
  [ "$wn" = "any" ] && n="any"
  [ "$b $p $h $n" = "$wb $wp $wh $wn" ] && return 0
  echo "selftest FAIL: $c: want branch=$wb push=$wp push-head=$wh exit=$wn, got $res"
  return 1
}

selftest() {
  local rc=0 out
  # the forms check 7 reads as "main is checked out" since issue #24: --track / -t with <remote>/main ...
  want 'main main main 0' 'switch --track origin/main' || rc=1
  want 'main main main 0' 'checkout --track origin/main' || rc=1
  want 'main main main 0' 'switch -t origin/main' || rc=1
  want 'main main main 0' 'checkout -t origin/main' || rc=1
  want 'main main main 0' 'switch --track=direct origin/main' || rc=1
  want 'main main main 0' 'switch --track refs/remotes/origin/main' || rc=1
  want 'main main main 0' 'switch --track remotes/origin/main' || rc=1
  # --no-track derives the name main in the same way (measured 2026-10-07, git 2.43.0; it was expected to be left
  # alone). The new branch has no upstream, so only the push of HEAD goes to main.
  want 'main refused main 0' 'switch --no-track origin/main' || rc=1
  want 'main refused main 0' 'checkout --no-track origin/main' || rc=1
  # ... and a rename of the current branch to main. The branch work has no upstream, so git's default refuses the
  # push without a ref; the push of HEAD goes to main. With an upstream origin/main the push without a ref goes too.
  want 'main refused main 0' 'branch -M main' || rc=1
  want 'main refused main 0' 'branch -m main' || rc=1
  want 'main refused main 0' 'branch --move main' || rc=1
  want 'main refused main 0' 'branch -m work main' || rc=1
  want 'main main main 0' 'switch -c work2 origin/main ; branch -M main' || rc=1
  # the forms it leaves alone: the new branch has another name, whatever the start point is called
  want 'feature refused feature 0' 'switch -c feature --track origin/main' || rc=1
  want 'feature refused feature 0' 'switch --track origin/main -c feature' || rc=1
  want 'feature feature feature 0' 'switch --track origin/feature' || rc=1
  want 'topic/main topic/main topic/main 0' 'switch --track origin/topic/main' || rc=1
  want 'feat/x refused feat/x 0' 'switch main ; switch main -c feat/x' || rc=1
  # a remote branch without --track is no local branch, and git branch without -m / -M does not move HEAD
  want 'detached refused refused 0' 'checkout origin/main' || rc=1
  # git rejects these two and the clone stays on work: switch takes no remote branch without --track or --detach,
  # and --track needs a name with a slash to derive the branch from
  want 'work refused work any' 'switch origin/main' || rc=1
  want 'work refused work any' 'switch --track main' || rc=1
  want 'work refused work 0' 'branch main' || rc=1
  want 'work refused work 0' 'branch -c main' || rc=1
  # a rename away from main ends the state; the rename of another branch leaves it
  want 'trunk refused trunk 0' 'switch main ; branch -m trunk' || rc=1
  want 'main main main 0' 'switch main ; branch -m work feat' || rc=1
  # issue #75 - three ways to write an option of switch / checkout, as measured 2026-10-07 with git 2.43.0.
  # An option that takes a value as its own word: the word behind --conflict is the style, the branch comes after
  # it. --recurse-submodules takes its value only with "=", so the word behind it is the branch. A style that git
  # does not know (here the word main) is rejected and the clone stays on work. --pathspec-from-file with a file
  # that names no path switches the branch.
  want 'main main main 0' 'switch --conflict diff3 main' || rc=1
  want 'main main main 0' 'checkout --conflict diff3 main' || rc=1
  want 'main main main 0' 'switch --conflict=diff3 main' || rc=1
  want 'main main main 0' 'switch --recurse-submodules main' || rc=1
  want 'feature feature feature 0' 'switch --conflict diff3 feature' || rc=1
  want 'work refused work any' 'switch --conflict main feature' || rc=1
  want 'main main main 0' 'checkout --pathspec-from-file /dev/null main' || rc=1
  # short options written as one word: every letter is an option, -t takes the rest of the word as its mode (so
  # -tf is the unknown mode f and git rejects it), and the letter d detaches
  want 'main main main 0' 'switch -ft origin/main' || rc=1
  want 'main main main 0' 'checkout -ft origin/main' || rc=1
  want 'main main main 0' 'switch -qt origin/main' || rc=1
  want 'main main main 0' 'switch -tdirect origin/main' || rc=1
  want 'feature feature feature 0' 'switch -ft origin/feature' || rc=1
  want 'work refused work any' 'switch -tf origin/main' || rc=1
  want 'detached refused refused 0' 'switch -fd origin/main' || rc=1
  want 'detached refused refused 0' 'switch --track origin/main ; switch -fd main' || rc=1
  # the name glued to a new-branch option, short and long. The new branch has no upstream (and after --orphan no
  # commit), so git's default refuses the push without a ref
  want 'main refused main 0' 'switch -cmain' || rc=1
  want 'main refused main 0' 'switch -Cmain' || rc=1
  want 'main refused main 0' 'checkout -bmain' || rc=1
  want 'main refused main 0' 'checkout -Bmain' || rc=1
  want 'main refused main 0' 'switch -fcmain' || rc=1
  want 'main refused main 0' 'switch --create=main' || rc=1
  want 'main refused main 0' 'switch --force-create=main' || rc=1
  want 'main refused refused 0' 'switch --orphan=main' || rc=1
  # ... and with another name glued to it: main is left, also when main is the start point behind the name
  want 'feat/x refused feat/x 0' 'switch main ; switch -cfeat/x' || rc=1
  want 'feat/x refused feat/x 0' 'switch main ; checkout -bfeat/x' || rc=1
  want 'feat/x refused feat/x 0' 'switch main ; switch --create=feat/x' || rc=1
  want 'feat/x refused feat/x 0' 'switch --track origin/main ; switch -cfeat/x main' || rc=1
  # what check 7 does not read (issue #77, named under "Still not seen" in scripts/gate.sh): git accepts a long
  # option cut down to a unique prefix, and rejects one that is ambiguous (--c: --create or --conflict)
  want 'main main main 0' 'switch --conf diff3 main' || rc=1
  want 'main main main 0' 'switch --tr origin/main' || rc=1
  want 'main refused main 0' 'switch --cre=main' || rc=1
  want 'detached refused refused 0' 'switch --track origin/main ; switch --det main' || rc=1
  want 'work refused work any' 'switch --c main' || rc=1
  # the readout itself: one line per command, the count line, and exit 2 without a command
  out="$(probe 'switch --track origin/main' 'branch main')"
  case "$out" in
    *"branch=main push=main push-head=main exit=0 | switch --track origin/main"*"branch-after: commands=2 on-main=1") ;;
    *) echo "selftest FAIL: readout of two commands: $out"; rc=1 ;;
  esac
  bash "${BASH_SOURCE[0]}" >/dev/null 2>&1
  [ $? -eq 2 ] || { echo "selftest FAIL: no command given, exit is not 2"; rc=1; }
  [ "$rc" -eq 0 ] && echo "selftest ok"
  return "$rc"
}

command -v git >/dev/null 2>&1 || { echo "branch-after-probe.sh: git not found" >&2; exit 2; }
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --help|-h) usage; exit 0 ;;
  "") usage >&2; exit 2 ;;
  -*) echo "branch-after-probe.sh: unknown option: $1" >&2; exit 2 ;;
esac
probe "$@"
exit $?
