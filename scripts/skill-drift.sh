#!/usr/bin/env bash
# skill-drift.sh — do the skills of this repo still match the copies of the same name in a skill store? Read-only.
#
# What it reports (offline, bash + find + cmp + diff only; it never writes to the store or to this repo):
#   one line per skill under skills/ that also exists in the store (default ~/.claude/skills):
#     SAME   <name>   every file is identical on both sides
#     EXTRA  <name>   everything the store holds is here verbatim; this repo has more (files that exist only here,
#                     or a declared appendix: the store's file is the exact start of the longer file here)
#     DRIFT  <name>   a shared file differs, or the store holds a file this repo lacks
#     FORK   <name>   differs, but the skill is declared as a deliberate variant: never synced in either direction
#     STALE  <name>   a declaration that no longer holds (nothing differs any more, or no such skill/file here)
#   under EXTRA/DRIFT/FORK one line per file: "<file> here=L store=L diff=D" (L = lines, D = lines of `diff` output),
#   "<file> only here", "<file> only in store" or "<file> store content verbatim, +N lines kept only here".
#   Skills that exist only here are counted, not listed.
# Declarations (default scripts/skill-drift-declared.txt), one per line, "#" starts the reason:
#     <name>                       the whole skill is a FORK
#     <name>/<file> +appendix      this file starts with the store's file byte for byte and keeps more below it
# Usage:   scripts/skill-drift.sh [--store DIR] [--root ROOT] [--declared FILE] [NAME ...]
#          scripts/skill-drift.sh --selftest   # 10 cases on temp fixtures; ~/.claude is never read or written
# Options: --store DIR      skill store to compare against (default ~/.claude/skills)
#          --root ROOT      repo to read skills/ from (default: the repo this script lives in)
#          --declared FILE  the declarations file (default scripts/skill-drift-declared.txt); --forks is an alias
#          NAME ...         only these skills (default: every skill dir under skills/)
# Output:  the lines above, then the last line
#          "skill-drift: in step same=S extra=E fork=F only-here=K" or
#          "skill-drift: DRIFT drift=D stale=T same=S extra=E fork=F only-here=K"
# Exit:    0 no undeclared drift · 1 drift or a stale declaration · 2 usage / store or root is not a directory
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SAME=0; EXTRA=0; DRIFT=0; FORK=0; STALE=0; ONLY_HERE=0
N_DIFFER=0; N_ONLY_HERE=0; N_ONLY_STORE=0; N_APPENDIX=0; N_STALE=0; DETAIL=""; STALE_LINES=""

# rel_files DIR — the relative paths of all files below DIR, sorted
rel_files() {
  (cd "$1" && find . -type f -printf '%P\n' | LC_ALL=C sort)
}

# is_fork FILE NAME — the whole skill NAME is declared (a line whose first word is NAME, without a mode)
is_fork() {
  [ -f "$1" ] || return 1
  awk -v n="$2" '{ sub(/#.*/, "") } $1 == n && NF == 1 { found = 1 } END { exit !found }' "$1"
}

# is_appendix FILE NAME/RELFILE — that file is declared "+appendix"
is_appendix() {
  [ -f "$1" ] || return 1
  awk -v n="$2" '{ sub(/#.*/, "") } $1 == n && $2 == "+appendix" { found = 1 } END { exit !found }' "$1"
}

# declared_keys FILE — the first word of every declaration (a skill name or name/file)
declared_keys() {
  [ -f "$1" ] || return 0
  awk '{ sub(/#.*/, "") } NF { print $1 }' "$1"
}

# is_prefix STOREFILE HEREFILE — the store file is the exact start of the longer file here
is_prefix() {
  local n
  n="$(wc -c < "$1")"
  [ "$n" -gt 0 ] && [ "$(wc -c < "$2")" -gt "$n" ] && head -c "$n" "$2" | cmp -s - "$1"
}

# compare_skill HERE STORE DECLARED NAME — sets N_DIFFER, N_ONLY_HERE, N_ONLY_STORE, N_APPENDIX, N_STALE,
# DETAIL and STALE_LINES for one skill dir pair
compare_skill() {
  local here="$1" store="$2" declared="$3" name="$4" f
  N_DIFFER=0; N_ONLY_HERE=0; N_ONLY_STORE=0; N_APPENDIX=0; N_STALE=0; DETAIL=""; STALE_LINES=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$store/$f" ]; then
      N_ONLY_HERE=$((N_ONLY_HERE + 1))
      DETAIL+="  $f only here"$'\n'
    elif cmp -s "$here/$f" "$store/$f"; then
      if is_appendix "$declared" "$name/$f"; then
        N_STALE=$((N_STALE + 1))
        STALE_LINES+="STALE  $name/$f (declared +appendix, but identical to the store)"$'\n'
      fi
    elif is_appendix "$declared" "$name/$f" && is_prefix "$store/$f" "$here/$f"; then
      N_APPENDIX=$((N_APPENDIX + 1))
      DETAIL+="  $f store content verbatim, +$(( $(wc -l < "$here/$f") - $(wc -l < "$store/$f") )) lines kept only here (declared appendix)"$'\n'
    else
      N_DIFFER=$((N_DIFFER + 1))
      DETAIL+="  $f here=$(wc -l < "$here/$f") store=$(wc -l < "$store/$f") diff=$(diff "$here/$f" "$store/$f" | wc -l)"$'\n'
      if is_appendix "$declared" "$name/$f"; then
        DETAIL+="  $f is declared +appendix, but the store's content is no longer its exact start"$'\n'
      fi
    fi
  done < <(rel_files "$here")
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$here/$f" ]; then
      N_ONLY_STORE=$((N_ONLY_STORE + 1))
      DETAIL+="  $f only in store"$'\n'
    fi
  done < <(rel_files "$store")
}

# run_compare ROOT STORE DECLARED [NAME ...] — prints the per-skill lines, sets the counters, returns 1 on drift/stale
run_compare() {
  local root="$1" store="$2" forks="$3" d name full=0
  shift 3
  local names=()
  SAME=0; EXTRA=0; DRIFT=0; FORK=0; STALE=0; ONLY_HERE=0
  if [ "$#" -eq 0 ]; then
    full=1
    for d in "$root"/skills/*/; do
      [ -d "$d" ] && names+=("$(basename "$d")")
    done
  else
    names=("$@")
  fi

  for name in ${names[@]+"${names[@]}"}; do
    if [ ! -d "$root/skills/$name" ]; then
      echo "STALE  $name (no skills/$name in this repo)"
      STALE=$((STALE + 1))
      continue
    fi
    if [ ! -d "$store/$name" ]; then
      ONLY_HERE=$((ONLY_HERE + 1))
      if is_fork "$forks" "$name"; then
        echo "STALE  $name (declared fork, but the store has no skill of that name)"
        STALE=$((STALE + 1))
      fi
      continue
    fi
    compare_skill "$root/skills/$name" "$store/$name" "$forks" "$name"
    printf '%s' "$STALE_LINES"
    STALE=$((STALE + N_STALE))
    if [ "$N_DIFFER" -eq 0 ] && [ "$N_ONLY_STORE" -eq 0 ]; then
      if is_fork "$forks" "$name"; then
        echo "STALE  $name (declared fork, but nothing differs)"
        STALE=$((STALE + 1))
      elif [ "$N_ONLY_HERE" -eq 0 ] && [ "$N_APPENDIX" -eq 0 ]; then
        echo "SAME   $name"
        SAME=$((SAME + 1))
      else
        echo "EXTRA  $name only-here=$N_ONLY_HERE appendix=$N_APPENDIX"
        printf '%s' "$DETAIL"
        EXTRA=$((EXTRA + 1))
      fi
    elif is_fork "$forks" "$name"; then
      echo "FORK   $name differs=$N_DIFFER only-store=$N_ONLY_STORE only-here=$N_ONLY_HERE (declared variant, not synced)"
      printf '%s' "$DETAIL"
      FORK=$((FORK + 1))
    else
      echo "DRIFT  $name differs=$N_DIFFER only-store=$N_ONLY_STORE only-here=$N_ONLY_HERE"
      printf '%s' "$DETAIL"
      DRIFT=$((DRIFT + 1))
    fi
  done

  # a full run also catches a declaration that names no skill dir or file of this repo
  if [ "$full" -eq 1 ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      if [ ! -e "$root/skills/$name" ]; then
        echo "STALE  $name (declared, but no skills/$name in this repo)"
        STALE=$((STALE + 1))
      fi
    done < <(declared_keys "$forks")
  fi
  [ $((DRIFT + STALE)) -eq 0 ]
}

report() {
  if run_compare "$@"; then
    echo "skill-drift: in step same=$SAME extra=$EXTRA fork=$FORK only-here=$ONLY_HERE"
  else
    echo "skill-drift: DRIFT drift=$DRIFT stale=$STALE same=$SAME extra=$EXTRA fork=$FORK only-here=$ONLY_HERE"
    return 1
  fi
}

# tree_sum DIR — checksum of every file below DIR (proves a run left the tree untouched)
tree_sum() {
  (cd "$1" && find . -type f -exec cksum {} + | LC_ALL=C sort)
}

selftest() {
  local t rc=0 out before_store before_root last
  t="$(mktemp -d)"
  mkdir -p "$t/root/skills/same" "$t/root/skills/extra/references" "$t/root/skills/drifted" \
           "$t/root/skills/variant" "$t/root/skills/local" "$t/root/scripts" \
           "$t/store/same" "$t/store/extra" "$t/store/drifted" "$t/store/variant" "$t/store/elsewhere"
  printf 'one\ntwo\n' > "$t/root/skills/same/SKILL.md"
  printf 'one\ntwo\n' > "$t/store/same/SKILL.md"
  printf 'e\n' > "$t/root/skills/extra/SKILL.md"
  printf 'e\n' > "$t/store/extra/SKILL.md"
  printf 'guide\n' > "$t/root/skills/extra/references/guide.md"
  printf 'a\nb\nc\n' > "$t/root/skills/drifted/SKILL.md"
  printf 'a\nB\nc\nd\n' > "$t/store/drifted/SKILL.md"
  printf 'project variant\n' > "$t/root/skills/variant/SKILL.md"
  printf 'generic template\n' > "$t/store/variant/SKILL.md"
  printf 'l\n' > "$t/root/skills/local/SKILL.md"
  printf 'z\n' > "$t/store/elsewhere/SKILL.md"
  : > "$t/noforks.txt"
  printf '# declared forks\nvariant   # project variant, the store holds the generic template\n' > "$t/forks.txt"
  before_store="$(tree_sum "$t/store")"
  before_root="$(tree_sum "$t/root")"

  # 1. no declaration: drifted and variant are both DRIFT, same is SAME, extra is EXTRA, local only counted
  out="$(report "$t/root" "$t/store" "$t/noforks.txt")" && { echo "selftest FAIL 1: drift accepted"; rc=1; }
  last="${out##*$'\n'}"
  [ "$last" = "skill-drift: DRIFT drift=2 stale=0 same=1 extra=1 fork=0 only-here=1" ] || { echo "selftest FAIL 1: last line: $last"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "  SKILL.md here=3 store=4 diff=6" || { echo "selftest FAIL 1: no file line for drifted: $out"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "  references/guide.md only here" || { echo "selftest FAIL 1: no only-here line"; rc=1; }
  printf '%s\n' "$out" | grep -q "elsewhere" && { echo "selftest FAIL 1: store-only skill listed"; rc=1; }

  # 2. variant declared as fork: FORK instead of DRIFT, still exit 1 because of drifted
  out="$(report "$t/root" "$t/store" "$t/forks.txt")" && { echo "selftest FAIL 2: drift accepted"; rc=1; }
  last="${out##*$'\n'}"
  [ "$last" = "skill-drift: DRIFT drift=1 stale=0 same=1 extra=1 fork=1 only-here=1" ] || { echo "selftest FAIL 2: last line: $last"; rc=1; }
  printf '%s\n' "$out" | grep -q "^FORK   variant " || { echo "selftest FAIL 2: no FORK line"; rc=1; }

  # 3. NAME filter: only the named skill is compared
  out="$(report "$t/root" "$t/store" "$t/forks.txt" same)" || { echo "selftest FAIL 3: single identical skill rejected"; rc=1; }
  [ "$out" = $'SAME   same\nskill-drift: in step same=1 extra=0 fork=0 only-here=0' ] || { echo "selftest FAIL 3: got: $out"; rc=1; }

  # 4. both trees are untouched after three runs (read-only)
  [ "$(tree_sum "$t/store")" = "$before_store" ] || { echo "selftest FAIL 4: store changed"; rc=1; }
  [ "$(tree_sum "$t/root")" = "$before_root" ] || { echo "selftest FAIL 4: root changed"; rc=1; }

  # 5. drifted brought in step (the fixture is edited here, not by the program): in step, the fork stays a FORK
  cp "$t/store/drifted/SKILL.md" "$t/root/skills/drifted/SKILL.md"
  out="$(report "$t/root" "$t/store" "$t/forks.txt")" || { echo "selftest FAIL 5: reconciled tree rejected: $out"; rc=1; }
  last="${out##*$'\n'}"
  [ "$last" = "skill-drift: in step same=2 extra=1 fork=1 only-here=1" ] || { echo "selftest FAIL 5: last line: $last"; rc=1; }

  # 6. the store gains a file this repo lacks: DRIFT with "only in store"
  printf 'new\n' > "$t/store/same/NOTES.md"
  out="$(report "$t/root" "$t/store" "$t/forks.txt")" && { echo "selftest FAIL 6: store-only file accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "  NOTES.md only in store" || { echo "selftest FAIL 6: no only-in-store line"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "DRIFT  same differs=0 only-store=1 only-here=0" || { echo "selftest FAIL 6: no DRIFT line: $out"; rc=1; }
  mv "$t/store/same/NOTES.md" "$t/NOTES.md.moved"

  # 7. stale declarations: a fork that no longer differs, and a declared name without a skill dir
  cp "$t/store/variant/SKILL.md" "$t/root/skills/variant/SKILL.md"
  printf 'variant\nghost  # was renamed\n' > "$t/forks.txt"
  out="$(report "$t/root" "$t/store" "$t/forks.txt")" && { echo "selftest FAIL 7: stale declarations accepted"; rc=1; }
  last="${out##*$'\n'}"
  [ "$last" = "skill-drift: DRIFT drift=0 stale=2 same=2 extra=1 fork=0 only-here=1" ] || { echo "selftest FAIL 7: last line: $last"; rc=1; }
  printf '%s\n' "$out" | grep -q "^STALE  ghost " || { echo "selftest FAIL 7: no STALE line for ghost"; rc=1; }

  # 8. usage: a store that is not a directory, and an unknown option -> exit 2
  bash "$SELF" --root "$t/root" --store "$t/nowhere" >/dev/null 2>&1
  [ "$?" -eq 2 ] || { echo "selftest FAIL 8: missing store did not exit 2"; rc=1; }
  bash "$SELF" --nonsense >/dev/null 2>&1
  [ "$?" -eq 2 ] || { echo "selftest FAIL 8: unknown option did not exit 2"; rc=1; }

  # 9. declared appendix: the file here starts with the store's file and keeps 2 more lines -> EXTRA, exit 0;
  #    the same file without the declaration is DRIFT
  printf 'one\ntwo\nkept 1\nkept 2\n' > "$t/root/skills/same/SKILL.md"
  printf 'same/SKILL.md +appendix   # the store content, then lines kept only here\n' > "$t/forks.txt"
  out="$(report "$t/root" "$t/store" "$t/forks.txt" same)" || { echo "selftest FAIL 9: declared appendix rejected: $out"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "EXTRA  same only-here=0 appendix=1" || { echo "selftest FAIL 9: no EXTRA line: $out"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "  SKILL.md store content verbatim, +2 lines kept only here (declared appendix)" || { echo "selftest FAIL 9: no appendix line: $out"; rc=1; }
  out="$(report "$t/root" "$t/store" "$t/noforks.txt" same)" && { echo "selftest FAIL 9: undeclared appendix accepted"; rc=1; }

  # 10. the declaration stops holding: the store's file changes (no longer the start) -> DRIFT;
  #     the file here loses its appendix (identical again) -> STALE
  printf 'one\nTWO\n' > "$t/store/same/SKILL.md"
  out="$(report "$t/root" "$t/store" "$t/forks.txt" same)" && { echo "selftest FAIL 10: changed store accepted under +appendix"; rc=1; }
  printf '%s\n' "$out" | grep -q -x "DRIFT  same differs=1 only-store=0 only-here=0" || { echo "selftest FAIL 10: no DRIFT line: $out"; rc=1; }
  printf '%s\n' "$out" | grep -q "no longer its exact start" || { echo "selftest FAIL 10: no explanation line"; rc=1; }
  cp "$t/store/same/SKILL.md" "$t/root/skills/same/SKILL.md"
  out="$(report "$t/root" "$t/store" "$t/forks.txt" same)" && { echo "selftest FAIL 10: stale +appendix accepted"; rc=1; }
  printf '%s\n' "$out" | grep -q "^STALE  same/SKILL.md " || { echo "selftest FAIL 10: no STALE line: $out"; rc=1; }

  rm -rf "$t"
  [ "$rc" -eq 0 ] && echo "selftest ok (10 cases)"
  return "$rc"
}

ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
STORE="$HOME/.claude/skills"
FORKS=""
NAMES=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --selftest) selftest; exit $? ;;
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$SELF"; exit 0 ;;
    --store|--root|--declared|--forks)
      [ "$#" -ge 2 ] || { echo "skill-drift.sh: $1 needs a value" >&2; exit 2; }
      case "$1" in
        --store) STORE="$2" ;;
        --root) ROOT="$2" ;;
        --declared|--forks) FORKS="$2" ;;
      esac
      shift 2
      ;;
    -*) echo "skill-drift.sh: unknown option $1" >&2; exit 2 ;;
    *) NAMES+=("$1"); shift ;;
  esac
done
[ -d "$ROOT/skills" ] || { echo "skill-drift.sh: no skills/ directory in: $ROOT" >&2; exit 2; }
[ -d "$STORE" ] || { echo "skill-drift.sh: store is not a directory: $STORE" >&2; exit 2; }
[ -n "$FORKS" ] || FORKS="$ROOT/scripts/skill-drift-declared.txt"
report "$ROOT" "$STORE" "$FORKS" ${NAMES[@]+"${NAMES[@]}"}
