#!/usr/bin/env bash
# install-status.sh — is a project's .claude in step with this repo? Read-only compare by name AND content.
#
# What it reports, one line per tool this repo installs (agents/*.md, commands/*.md, skills/<name>/ without evals/):
#   SAME     present there, every file identical
#   DIFFERS  present there, but a file differs or is missing -> install.sh would overwrite/add it (files listed)
#   MISSING  not there                                        -> install.sh would add it
#   EXTRA    in the destination's agents/, commands/ or skills/ but not from this repo -> install.sh leaves it alone
#   NOTE     the destination skill carries an evals/ folder   -> install.sh leaves that folder as it was (since
#            issue #8; before, it removed the folder and this line was a WARN). Not counted, it is no gap.
# The destination is never written. --rehearse copies its agents/, commands/ and skills/ into a temp dir, runs
# install.sh into that copy and prints the status before and after; the temp dir is removed afterwards.
# Usage:   scripts/install-status.sh [--source ROOT] <destination>             # <destination> = the .claude directory
#          scripts/install-status.sh [--source ROOT] --rehearse <destination>  # what would an install change?
#          scripts/install-status.sh --selftest                                # 8 cases on temp fixtures
# Options: --source ROOT  repo to compare against (default: the repo this script lives in)
#          --rehearse     status of a temp copy before and after install.sh; the real destination stays untouched
# Output:  one line per tool (SAME · DIFFERS · MISSING · EXTRA, and NOTE for an evals/ folder there), then the last line
#          "install-status: in step same=S extra=E" or "install-status: BEHIND missing=M differs=D same=S extra=E"
# Exit:    0 in step · 1 behind (or the rehearsed install failed) · 2 usage / destination is not a directory
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
MISSING=0
DIFFERS=0
SAME=0
EXTRA=0

# here_date ROOT PATH — date of the last commit that touched PATH in ROOT, or "not in git"
here_date() {
  local d
  d="$(git -C "$1" log -1 --format=%cs -- "$2" 2>/dev/null)"
  printf '%s' "${d:-not in git}"
}

# differs_detail ROOT PATH_IN_ROOT LABEL DEST_FILE — one indented line with both dates, to judge which side is newer
differs_detail() {
  printf '    differs: %s (here: last commit %s · there: modified %s)\n' \
    "$3" "$(here_date "$1" "$2")" "$(date -r "$4" +%F)"
}

# status SRC DEST — prints the report, sets the four counters, returns 1 when something is missing or differs
status() {
  local src="$1" dest="$2" kind f d name rel hint
  local -a details
  MISSING=0
  DIFFERS=0
  SAME=0
  EXTRA=0

  for kind in agents commands; do
    for f in "$src/$kind"/*.md; do
      [ -f "$f" ] || continue
      name="$(basename "$f")"
      if [ ! -f "$dest/$kind/$name" ]; then
        echo "MISSING  $kind/$name"
        MISSING=$((MISSING + 1))
      elif cmp -s "$f" "$dest/$kind/$name"; then
        echo "SAME     $kind/$name"
        SAME=$((SAME + 1))
      else
        echo "DIFFERS  $kind/$name"
        DIFFERS=$((DIFFERS + 1))
        differs_detail "$src" "$kind/$name" "$name" "$dest/$kind/$name"
      fi
    done
  done

  for d in "$src"/skills/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ ! -d "$dest/skills/$name" ]; then
      echo "MISSING  skills/$name/"
      MISSING=$((MISSING + 1))
      continue
    fi
    details=()
    while IFS= read -r rel; do
      case "$rel" in evals/*) continue ;; esac   # install.sh does not install a skill's evals/
      if [ ! -f "$dest/skills/$name/$rel" ]; then
        details+=("    missing file: $rel")
      elif ! cmp -s "$d$rel" "$dest/skills/$name/$rel"; then
        details+=("$(differs_detail "$src" "skills/$name/$rel" "$rel" "$dest/skills/$name/$rel")")
      fi
    done < <(cd "$d" && find . -type f -printf '%P\n' | sort)
    if [ "${#details[@]}" -eq 0 ]; then
      echo "SAME     skills/$name/"
      SAME=$((SAME + 1))
    else
      echo "DIFFERS  skills/$name/"
      DIFFERS=$((DIFFERS + 1))
      printf '%s\n' "${details[@]}"
    fi
    while IFS= read -r rel; do
      case "$rel" in evals/*) continue ;; esac
      [ -f "$d$rel" ] || echo "    only there: $rel (install.sh keeps it)"
    done < <(cd "$dest/skills/$name" && find . -type f -printf '%P\n' | sort)
    # Superseded by issue #8 (install.sh no longer removes an evals/ folder the destination already has):
    #   echo "WARN     skills/$name/evals/ exists there - install.sh would remove that folder"
    if [ -d "$dest/skills/$name/evals" ]; then
      echo "NOTE     skills/$name/evals/ exists there - install.sh leaves that folder as it was"
    fi
  done

  for kind in agents commands; do
    for f in "$dest/$kind"/*.md; do
      [ -f "$f" ] || continue
      name="$(basename "$f")"
      [ -f "$src/$kind/$name" ] && continue
      hint=""
      [ -d "$src/skills/${name%.md}" ] && hint=" (this repo has a skill of that name: skills/${name%.md}/)"
      echo "EXTRA    $kind/$name$hint"
      EXTRA=$((EXTRA + 1))
    done
  done
  for d in "$dest"/skills/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    [ -d "$src/skills/$name" ] && continue
    echo "EXTRA    skills/$name/"
    EXTRA=$((EXTRA + 1))
  done

  if [ $((MISSING + DIFFERS)) -eq 0 ]; then
    echo "install-status: in step same=$SAME extra=$EXTRA"
  else
    echo "install-status: BEHIND missing=$MISSING differs=$DIFFERS same=$SAME extra=$EXTRA"
    return 1
  fi
}

# rehearse SRC DEST — status of a temp copy of DEST before and after install.sh; DEST itself is only read
rehearse() {
  local src="$1" dest="$2" tmp kind rc
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/copy"
  for kind in agents commands skills; do
    if [ -d "$dest/$kind" ]; then cp -a "$dest/$kind" "$tmp/copy/"; fi
  done
  echo "== before: $dest (read from a temp copy)"
  status "$src" "$tmp/copy"
  echo "== after: install.sh into the temp copy ($dest itself is not written)"
  if bash "$src/install.sh" "$tmp/copy" >/dev/null 2>&1; then
    status "$src" "$tmp/copy"
    rc=$?
  else
    echo "install-status: install.sh failed in the rehearsal"
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

selftest() {
  local t rc=0 out code
  t="$(mktemp -d)"
  mkdir -p "$t/src/agents" "$t/src/commands" "$t/src/skills/x/refs" "$t/src/skills/x/evals" "$t/src/skills/y"
  printf 'a\n' > "$t/src/agents/a.md"
  printf 'c\n' > "$t/src/commands/c.md"
  printf 'x\n' > "$t/src/skills/x/SKILL.md"
  printf 'r\n' > "$t/src/skills/x/refs/r.md"
  printf 'e\n' > "$t/src/skills/x/evals/e.json"
  printf 'y\n' > "$t/src/skills/y/SKILL.md"
  cp "$(dirname "$SELF")/../install.sh" "$t/src/install.sh"

  # 1. fresh install: 4 tools, all SAME; the source's evals/ is not installed and does not count as a gap
  bash "$t/src/install.sh" "$t/fresh" >/dev/null 2>&1 || { echo "selftest FAIL: fixture install failed"; rc=1; }
  out="$(status "$t/src" "$t/fresh")" || { echo "selftest FAIL: fresh install reported behind"; rc=1; }
  [ "${out##*$'\n'}" = "install-status: in step same=4 extra=0" ] || { echo "selftest FAIL: fresh, got: ${out##*$'\n'}"; rc=1; }

  # 2. empty destination: everything MISSING
  mkdir -p "$t/empty"
  out="$(status "$t/src" "$t/empty")" && { echo "selftest FAIL: empty destination accepted"; rc=1; }
  [ "${out##*$'\n'}" = "install-status: BEHIND missing=4 differs=0 same=0 extra=0" ] || { echo "selftest FAIL: empty, got: ${out##*$'\n'}"; rc=1; }

  # 3. partial destination: agent same, command + skill y missing, skill x with a changed and a missing file
  mkdir -p "$t/part/agents" "$t/part/skills/x"
  cp "$t/src/agents/a.md" "$t/part/agents/a.md"
  printf 'older x\n' > "$t/part/skills/x/SKILL.md"
  out="$(status "$t/src" "$t/part")" && { echo "selftest FAIL: partial destination accepted"; rc=1; }
  [ "${out##*$'\n'}" = "install-status: BEHIND missing=2 differs=1 same=1 extra=0" ] || { echo "selftest FAIL: partial, got: ${out##*$'\n'}"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "MISSING  commands/c.md" || { echo "selftest FAIL: no MISSING line for c.md"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "DIFFERS  skills/x/" || { echo "selftest FAIL: no DIFFERS line for x"; rc=1; }
  printf '%s\n' "$out" | grep -q "^    differs: SKILL.md (here: last commit not in git · there: modified " || { echo "selftest FAIL: no differs detail"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "    missing file: refs/r.md" || { echo "selftest FAIL: no missing-file detail"; rc=1; }

  # 4. extras: foreign agent, a command named like a skill here, a foreign skill, a file only there, an evals/ there
  cp -r "$t/fresh" "$t/extra"
  mkdir -p "$t/extra/skills/z" "$t/extra/skills/x/evals"
  printf 'b\n' > "$t/extra/agents/bb.md"
  printf 'y\n' > "$t/extra/commands/y.md"
  printf 'z\n' > "$t/extra/skills/z/SKILL.md"
  printf 'n\n' > "$t/extra/skills/x/notes.md"
  printf 'e\n' > "$t/extra/skills/x/evals/own.json"
  out="$(status "$t/src" "$t/extra")" || { echo "selftest FAIL: extras counted as behind"; rc=1; }
  [ "${out##*$'\n'}" = "install-status: in step same=4 extra=3" ] || { echo "selftest FAIL: extras, got: ${out##*$'\n'}"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "EXTRA    commands/y.md (this repo has a skill of that name: skills/y/)" || { echo "selftest FAIL: no same-name hint"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "    only there: notes.md (install.sh keeps it)" || { echo "selftest FAIL: no only-there line"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "NOTE     skills/x/evals/ exists there - install.sh leaves that folder as it was" || { echo "selftest FAIL: no evals note"; rc=1; }
  printf '%s\n' "$out" | grep -q "would remove that folder" && { echo "selftest FAIL: the report still says install.sh would remove evals/"; rc=1; }

  # 5. rehearsal of the partial destination: behind before, in step after, and the destination itself unchanged
  out="$(rehearse "$t/src" "$t/part")" || { echo "selftest FAIL: rehearsal did not end in step"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "install-status: BEHIND missing=2 differs=1 same=1 extra=0" || { echo "selftest FAIL: rehearsal has no before line"; rc=1; }
  [ "${out##*$'\n'}" = "install-status: in step same=4 extra=0" ] || { echo "selftest FAIL: rehearsal after, got: ${out##*$'\n'}"; rc=1; }
  [ ! -e "$t/part/commands" ] && [ ! -e "$t/part/skills/y" ] && [ "$(cat "$t/part/skills/x/SKILL.md")" = "older x" ] \
    || { echo "selftest FAIL: rehearsal wrote into the destination"; rc=1; }

  # 6. usage errors: no destination, destination that is not a directory, unknown option -> exit 2
  bash "$SELF" >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL: no destination gave exit $code"; rc=1; }
  bash "$SELF" "$t/nope" >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL: missing destination dir gave exit $code"; rc=1; }
  bash "$SELF" --bogus "$t/fresh" >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL: unknown option gave exit $code"; rc=1; }

  # 7. command line with --source: exit 0 in step, exit 1 behind
  bash "$SELF" --source "$t/src" "$t/fresh" >/dev/null 2>&1; code=$?
  [ "$code" -eq 0 ] || { echo "selftest FAIL: cli in step gave exit $code"; rc=1; }
  bash "$SELF" --source "$t/src" "$t/part" >/dev/null 2>&1; code=$?
  [ "$code" -eq 1 ] || { echo "selftest FAIL: cli behind gave exit $code"; rc=1; }

  # 8. what the NOTE line and the "only there" line say is what install.sh does: an install into the extras
  #    destination keeps its evals/own.json and its notes.md, adds nothing next to own.json (the source's evals/ is
  #    not installed), and the status is the same afterwards. This case fails with an installer that removes evals/.
  bash "$t/src/install.sh" "$t/extra" >/dev/null 2>&1 || { echo "selftest FAIL: install into the extras destination failed"; rc=1; }
  [ "$(cat "$t/extra/skills/x/evals/own.json" 2>/dev/null)" = "e" ] || { echo "selftest FAIL: install.sh did not leave the destination's evals/own.json as it was"; rc=1; }
  [ ! -e "$t/extra/skills/x/evals/e.json" ] || { echo "selftest FAIL: install.sh installed the source's evals/"; rc=1; }
  [ -f "$t/extra/skills/x/notes.md" ] || { echo "selftest FAIL: install.sh did not keep a file that is only there"; rc=1; }
  out="$(status "$t/src" "$t/extra")" || { echo "selftest FAIL: extras destination behind after an install"; rc=1; }
  [ "${out##*$'\n'}" = "install-status: in step same=4 extra=3" ] || { echo "selftest FAIL: extras after install, got: ${out##*$'\n'}"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "NOTE     skills/x/evals/ exists there - install.sh leaves that folder as it was" || { echo "selftest FAIL: no evals note after the install"; rc=1; }

  rm -rf "$t"
  [ "$rc" -eq 0 ] && echo "selftest ok (8 cases)"
  return "$rc"
}

SRC="$(cd "$(dirname "$SELF")/.." && pwd)"
MODE=status
DEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) selftest; exit $? ;;
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$SELF"; exit 0 ;;
    --source)
      [ $# -ge 2 ] || { echo "install-status.sh: --source needs a directory" >&2; exit 2; }
      SRC="$2"
      shift 2
      ;;
    --rehearse) MODE=rehearse; shift ;;
    -*) echo "install-status.sh: unknown option $1" >&2; exit 2 ;;
    *)
      [ -z "$DEST" ] || { echo "install-status.sh: one destination only" >&2; exit 2; }
      DEST="$1"
      shift
      ;;
  esac
done
[ -n "$DEST" ] || { echo "Usage: scripts/install-status.sh [--source ROOT] [--rehearse] <destination>   (--help for details)" >&2; exit 2; }
[ -d "$DEST" ] || { echo "install-status.sh: not a directory: $DEST" >&2; exit 2; }
[ -d "$SRC/skills" ] || { echo "install-status.sh: no skills/ under --source $SRC" >&2; exit 2; }
if [ "$MODE" = rehearse ]; then rehearse "$SRC" "$DEST"; else status "$SRC" "$DEST"; fi
