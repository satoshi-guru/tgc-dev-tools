#!/usr/bin/env bash
# board-prompt-check.sh — does what a lane of this board reads in its order still carry a retired sentence? Read-only.
#
# What it does: an order for a lane has two sources that are written at different times. The role file
# (.claude/agents/bb-*.md, in this repo, changed by pull request) and the board's project texts (Warum, Grenzen,
# Selbstpruefung ... in boards.json["prompt"] of the board directory, outside this repo, written at onboarding).
# Issue #59: the role file had stopped saying that the skills "have drifted" (issue #14), the board text still said
# it, and a lane read both statements in one order. This program looks for every phrase of
# scripts/board-prompt-retired.txt in both sources:
#   board  the texts the driver puts into an order, read the way the driver gets them: through the board kernel
#          (`blackboard.py --dir BOARD prompt-texte`, which without an option only shows the effective texts, the
#          kernel's defaults included). boards.json is never opened or written by this program.
#   role   every .claude/agents/*.md of the repo
# A phrase is matched as fixed text, upper and lower case alike, line by line: a phrase that is wrapped over two
# lines of a role file is not found. Changing a board text is not this program's job: that is
# `blackboard.py --dir BOARD prompt-texte --warum "..."` (it writes only the key that is named).
# Not a gate check: the board directory differs per machine and changes without a commit here.
# Usage:   scripts/board-prompt-check.sh [--board DIR] [--kernel FILE] [--root ROOT] [--retired FILE]
#          scripts/board-prompt-check.sh --selftest   # 7 cases on temp fixtures; ~/.claude/boards is never read or written
# Options: --board DIR     board directory that holds boards.json (default $BLACKBOARD_DIR, else ~/.claude/boards/tgc-dev-tools)
#          --kernel FILE   the board kernel (default ~/.claude/scripts/dev/blackboard.py)
#          --root ROOT     repo to read .claude/agents/*.md from (default: the repo this script lives in, also through a symlink)
#          --retired FILE  the phrases file (default ROOT/scripts/board-prompt-retired.txt)
# Output:  one line per hit, 'STALE board <key>: "<phrase>"' or 'STALE role <file>:<line>: "<phrase>"', then the last line
#          "board-prompt: ok phrases=P texts=T role-files=R" or "board-prompt: STALE hits=K phrases=P texts=T role-files=R"
# Exit:    0 no retired phrase · 1 at least one · 2 usage / nothing could be read (no boards.json in DIR, no kernel,
#          the kernel failed or printed no text, no phrase in FILE) - a check that read nothing is never green
set -uo pipefail

# real_path FILE — absolute path of FILE with every symlink resolved: a link to the file by readlink (a chain of
# at most 40), a link in the directory part by cd -P
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

SELF="$(real_path "${BASH_SOURCE[0]}")"
STORE_KERNEL="$HOME/.claude/scripts/dev/blackboard.py"
# the keys the kernel prints, one "<key>: <text>" line each (a text with a line break continues on the next line)
KEYS="beleg_ordner warum grenzen selbstpruefung bb"

# phrases FILE — prints the phrases of FILE, one per line: blanks around a line are cut, # lines and empty lines left out
phrases() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in "" | "#"*) continue ;; esac
    printf '%s\n' "$line"
  done < "$1"
}

# check BOARD KERNEL ROOT RETIRED — prints the lines described under Output; returns 0 ok, 1 stale, 2 nothing read
check() {
  local board="$1" kernel="$2" root="$3" retired="$4"
  local list out code line k p f rel n key="" texts=0 hits=0 nphr=0 roles=0
  [ -f "$retired" ] || { echo "board-prompt-check.sh: no phrases file: $retired" >&2; return 2; }
  list="$(phrases "$retired")"
  [ -n "$list" ] || { echo "board-prompt-check.sh: no phrase in $retired - nothing would be checked" >&2; return 2; }
  while IFS= read -r p; do nphr=$((nphr + 1)); done <<< "$list"
  [ -f "$board/boards.json" ] || { echo "board-prompt-check.sh: no boards.json in $board" >&2; return 2; }
  [ -f "$kernel" ] || { echo "board-prompt-check.sh: board kernel not found: $kernel" >&2; return 2; }
  out="$(BLACKBOARD_DIR="$board" python3 "$kernel" --dir "$board" prompt-texte 2>&1)"
  code=$?
  [ "$code" -eq 0 ] || { echo "board-prompt-check.sh: the kernel ended with exit $code: ${out##*$'\n'}" >&2; return 2; }

  while IFS= read -r line; do
    for k in $KEYS; do
      case "$line" in "$k:"*) key="$k"; texts=$((texts + 1)); break ;; esac
    done
    [ -n "$key" ] || continue
    while IFS= read -r p; do
      if printf '%s\n' "$line" | grep -q -i -F -e "$p"; then
        echo "STALE board $key: \"$p\""
        hits=$((hits + 1))
      fi
    done <<< "$list"
  done <<< "$out"
  [ "$texts" -gt 0 ] || { echo "board-prompt-check.sh: the kernel printed no prompt text (none of: $KEYS)" >&2; return 2; }

  for f in "$root"/.claude/agents/*.md; do
    [ -f "$f" ] || continue
    roles=$((roles + 1))
    rel="${f#"$root"/}"
    while IFS= read -r p; do
      while IFS= read -r n; do
        [ -n "$n" ] || continue
        echo "STALE role $rel:${n%%:*}: \"$p\""
        hits=$((hits + 1))
      done <<< "$(grep -n -i -F -e "$p" "$f")"
    done <<< "$list"
  done

  if [ "$hits" -eq 0 ]; then
    echo "board-prompt: ok phrases=$nphr texts=$texts role-files=$roles"
  else
    echo "board-prompt: STALE hits=$hits phrases=$nphr texts=$texts role-files=$roles"
    return 1
  fi
}

# fixture DIR WARUM — a board directory DIR/board (boards.json + the texts the stub kernel prints) and a repo
# DIR/root with two role files and a phrases file that holds one phrase
fixture() {
  local d="$1" warum="$2"
  mkdir -p "$d/board" "$d/root/.claude/agents" "$d/root/scripts"
  printf '{}\n' > "$d/board/boards.json"
  printf '%s\n' "beleg_ordner: " "warum: $warum" "grenzen: only your item; never delete." \
    "selbstpruefung: the gate is green.   (Default)" "bb: python3 kernel.py" > "$d/board/texts"
  printf '%s\n' "# Role a" "" "Four skills also exist in the store." > "$d/root/.claude/agents/bb-a.md"
  printf '%s\n' "# Role b" "" "Run the readout first." > "$d/root/.claude/agents/bb-b.md"
  printf '%s\n' "# a comment that names a retired sentence is no phrase" "" "have drifted" > "$d/root/scripts/board-prompt-retired.txt"
}

selftest() {
  local t rc=0 out code stub sum lines
  t="$(mktemp -d)"
  mkdir -p "$t/cwd" "$t/via"
  # the stub kernel prints DIR/texts, the way the real one prints the effective texts
  stub="$t/stub.py"
  printf '%s\n' 'import pathlib' 'import sys' 'd = sys.argv[sys.argv.index("--dir") + 1]' \
    'sys.stdout.write(pathlib.Path(d, "texts").read_text())' > "$stub"

  # 1. nothing retired in the board texts or the role files: ok, exit 0, every count in the last line
  fixture "$t/c1" "a wrong instruction is repeated; four skills also exist in the store."
  out="$(check "$t/c1/board" "$stub" "$t/c1/root" "$t/c1/root/scripts/board-prompt-retired.txt" 2>&1)"; code=$?
  [ "$code" -eq 0 ] || { echo "selftest FAIL 1: clean fixture gives exit $code: $out"; rc=1; }
  [ "$out" = "board-prompt: ok phrases=1 texts=5 role-files=2" ] || { echo "selftest FAIL 1: got: $out"; rc=1; }

  # 2. the case of issue #59: the board text carries the phrase (other case), the role files do not
  fixture "$t/c2" "a wrong instruction is repeated, and several skills HAVE Drifted from the copies."
  out="$(check "$t/c2/board" "$stub" "$t/c2/root" "$t/c2/root/scripts/board-prompt-retired.txt" 2>&1)"; code=$?
  [ "$code" -eq 1 ] || { echo "selftest FAIL 2: stale board text gives exit $code"; rc=1; }
  printf '%s\n' "$out" | grep -q -x 'STALE board warum: "have drifted"' || { echo "selftest FAIL 2: no line for the board text: $out"; rc=1; }
  [ "${out##*$'\n'}" = "board-prompt: STALE hits=1 phrases=1 texts=5 role-files=2" ] || { echo "selftest FAIL 2: last line: ${out##*$'\n'}"; rc=1; }

  # 3. the case of issue #14: a role file carries the phrase in line 3, the board text does not
  fixture "$t/c3" "four skills also exist in the store."
  printf '%s\n' "# Role b" "" "Skills here have drifted from the copies." > "$t/c3/root/.claude/agents/bb-b.md"
  out="$(check "$t/c3/board" "$stub" "$t/c3/root" "$t/c3/root/scripts/board-prompt-retired.txt" 2>&1)"; code=$?
  [ "$code" -eq 1 ] || { echo "selftest FAIL 3: stale role file gives exit $code"; rc=1; }
  printf '%s\n' "$out" | grep -q -x 'STALE role .claude/agents/bb-b.md:3: "have drifted"' || { echo "selftest FAIL 3: no line for the role file: $out"; rc=1; }
  printf '%s\n' "$out" | grep -q '^STALE board' && { echo "selftest FAIL 3: a clean board text was reported: $out"; rc=1; }

  # 4. two phrases, and a text with a line break: the hit on the second line is counted for the key above it
  fixture "$t/c4" "four skills also exist in the store."
  printf '%s\n' "# first" "have drifted" "" "  compare by hand  " > "$t/c4/root/scripts/board-prompt-retired.txt"
  printf '%s\n' "beleg_ordner: " "warum: fine." "grenzen: only your item;" "then Compare By Hand, always." \
    "selbstpruefung: green." "bb: kernel" > "$t/c4/board/texts"
  out="$(check "$t/c4/board" "$stub" "$t/c4/root" "$t/c4/root/scripts/board-prompt-retired.txt" 2>&1)"; code=$?
  [ "$code" -eq 1 ] || { echo "selftest FAIL 4: second phrase on a continued line gives exit $code"; rc=1; }
  printf '%s\n' "$out" | grep -q -x 'STALE board grenzen: "compare by hand"' || { echo "selftest FAIL 4: hit not counted for grenzen: $out"; rc=1; }
  [ "${out##*$'\n'}" = "board-prompt: STALE hits=1 phrases=2 texts=5 role-files=2" ] || { echo "selftest FAIL 4: last line: ${out##*$'\n'}"; rc=1; }

  # 5. nothing read is never green: exit 2 for a phrases file without a phrase, a board directory without
  #    boards.json, a missing kernel, a kernel that fails, a kernel that prints no text, an unknown option
  fixture "$t/c5" "several skills have drifted."
  printf '%s\n' "# only a comment" "" > "$t/c5/empty.txt"
  check "$t/c5/board" "$stub" "$t/c5/root" "$t/c5/empty.txt" >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL 5: a phrases file without a phrase gives exit $code, want 2"; rc=1; }
  check "$t/c5/root" "$stub" "$t/c5/root" "$t/c5/root/scripts/board-prompt-retired.txt" >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL 5: a directory without boards.json gives exit $code, want 2"; rc=1; }
  check "$t/c5/board" "$t/absent.py" "$t/c5/root" "$t/c5/root/scripts/board-prompt-retired.txt" >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL 5: a missing kernel gives exit $code, want 2"; rc=1; }
  printf '%s\n' 'import sys' 'print("warum: several skills have drifted.")' 'sys.exit(3)' > "$t/failing.py"
  check "$t/c5/board" "$t/failing.py" "$t/c5/root" "$t/c5/root/scripts/board-prompt-retired.txt" >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL 5: a failing kernel gives exit $code, want 2"; rc=1; }
  printf '%s\n' 'print("nothing to show")' > "$t/silent.py"
  check "$t/c5/board" "$t/silent.py" "$t/c5/root" "$t/c5/root/scripts/board-prompt-retired.txt" >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL 5: a kernel without a text line gives exit $code, want 2"; rc=1; }
  bash "$SELF" --nope >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL 5: an unknown option gives exit $code, want 2"; rc=1; }
  bash "$SELF" --board >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL 5: an option without its value gives exit $code, want 2"; rc=1; }

  # 6. started through a symlink from another directory: root and phrases file are those of the repo the program
  #    file lives in, not of the directory above the link
  cp "$SELF" "$t/c2/root/scripts/board-prompt-check.sh"
  ln -s "$t/c2/root/scripts/board-prompt-check.sh" "$t/via/check.sh"
  out="$(cd "$t/cwd" && bash "$t/via/check.sh" --board "$t/c2/board" --kernel "$stub" 2>&1)"; code=$?
  [ "$code" -eq 1 ] || { echo "selftest FAIL 6: started through a link gives exit $code, want 1: $out"; rc=1; }
  [ "${out##*$'\n'}" = "board-prompt: STALE hits=1 phrases=1 texts=5 role-files=2" ] || { echo "selftest FAIL 6: last line: ${out##*$'\n'}"; rc=1; }

  # 7. the real kernel on a temp board (skipped with a note when the store is absent): its output is read the same
  #    way, the text set with prompt-texte is found, and the check leaves boards.json and the audit log as they were
  if [ -f "$STORE_KERNEL" ]; then
    mkdir -p "$t/real"
    fixture "$t/c7" "unused"
    BLACKBOARD_DIR="$t/real" python3 "$STORE_KERNEL" --dir "$t/real" init --project fixture --boards a >/dev/null 2>&1
    BLACKBOARD_DIR="$t/real" python3 "$STORE_KERNEL" --dir "$t/real" prompt-texte \
      --warum "a wrong instruction is repeated, and several skills have drifted from the copies." >/dev/null 2>&1
    sum="$(cksum < "$t/real/boards.json")"
    lines="$(cat "$t/real"/audit.log.jsonl 2>/dev/null | wc -l)"
    out="$(check "$t/real" "$STORE_KERNEL" "$t/c7/root" "$t/c7/root/scripts/board-prompt-retired.txt" 2>&1)"; code=$?
    [ "$code" -eq 1 ] || { echo "selftest FAIL 7: real kernel, stale text gives exit $code: $out"; rc=1; }
    printf '%s\n' "$out" | grep -q -x 'STALE board warum: "have drifted"' || { echo "selftest FAIL 7: real kernel, no line for the text: $out"; rc=1; }
    [ "${out##*$'\n'}" = "board-prompt: STALE hits=1 phrases=1 texts=5 role-files=2" ] || { echo "selftest FAIL 7: real kernel, last line: ${out##*$'\n'}"; rc=1; }
    [ "$(cksum < "$t/real/boards.json")" = "$sum" ] || { echo "selftest FAIL 7: the check changed boards.json"; rc=1; }
    [ "$(cat "$t/real"/audit.log.jsonl 2>/dev/null | wc -l)" = "$lines" ] || { echo "selftest FAIL 7: the check wrote to the audit log"; rc=1; }
    BLACKBOARD_DIR="$t/real" python3 "$STORE_KERNEL" --dir "$t/real" prompt-texte \
      --warum "a wrong instruction is repeated; four skills also exist in the store." >/dev/null 2>&1
    out="$(check "$t/real" "$STORE_KERNEL" "$t/c7/root" "$t/c7/root/scripts/board-prompt-retired.txt" 2>&1)"; code=$?
    [ "$code" -eq 0 ] || { echo "selftest FAIL 7: real kernel, corrected text gives exit $code: $out"; rc=1; }
    [ "$out" = "board-prompt: ok phrases=1 texts=5 role-files=2" ] || { echo "selftest FAIL 7: real kernel, corrected text: $out"; rc=1; }
  else
    echo "note: case 7 skipped (no board kernel at $STORE_KERNEL)"
  fi

  rm -rf "$t"
  [ "$rc" -eq 0 ] && echo "selftest ok (7 cases)"
  return "$rc"
}

BOARD="${BLACKBOARD_DIR:-$HOME/.claude/boards/tgc-dev-tools}"
KERNEL="$STORE_KERNEL"
ROOT="$(cd -P "$(dirname "$SELF")/.." && pwd)"
RETIRED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) selftest; exit $? ;;
    -h | --help) awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$SELF"; exit 0 ;;
    --board | --kernel | --root | --retired)
      [ $# -ge 2 ] || { echo "board-prompt-check.sh: $1 needs a value" >&2; exit 2; }
      case "$1" in
        --board) BOARD="$2" ;;
        --kernel) KERNEL="$2" ;;
        --root) ROOT="$2" ;;
        --retired) RETIRED="$2" ;;
      esac
      shift 2 ;;
    *) echo "board-prompt-check.sh: unknown argument $1 (usage: --help)" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "board-prompt-check.sh: not a directory: $ROOT" >&2; exit 2; }
[ -n "$RETIRED" ] || RETIRED="$ROOT/scripts/board-prompt-retired.txt"
check "$BOARD" "$KERNEL" "$ROOT" "$RETIRED"
