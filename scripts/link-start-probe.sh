#!/usr/bin/env bash
# link-start-probe.sh — does a program give the same answer when it is started through a symlink? Read-only.
#
# What it does: starts PROGRAM [ARG ...] five ways, each time in an empty temp directory, and compares the last
# output line and the exit code of every start with the direct one (issue #29: scripts/gate.sh started through a
# link took the directory above the link for the repo and ended with "gate: ok" without having read the repo).
#   direct    by its real path
#   file      through a link to the file (absolute target), placed in <tmp>/file/sub/
#   relative  through a link to the file with a relative target, placed in <tmp>/rel/sub/ (needs `ln -sr`; left out
#             with a note where ln cannot do that)
#   chain     through a link to the file link above, placed in <tmp>/chain/sub/
#   dir       through a link to the program's directory, placed in <tmp>/dir/ under the directory's own name
# The links live in a temp dir that is removed at the end; nothing is written next to PROGRAM.
# Usage:   scripts/link-start-probe.sh PROGRAM [ARG ...]   # PROGRAM is run as it is when executable, else with bash
#          scripts/link-start-probe.sh --selftest          # 6 cases on temp fixtures
# Output:  one line per start "<how>: exit=N last=<last output line>", then the last line
#          "link-start: same starts=N" or "link-start: DIFFERENT differing=K starts=N"
# Exit:    0 every start gives the direct result · 1 at least one differs · 2 usage / PROGRAM is not a file
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

# probe PROGRAM [ARG ...] — prints the lines described under Output; returns 0 same, 1 different
probe() {
  local real dir base t how path out code res first="" diff=0 starts=0
  real="$(real_path "$1")"
  shift
  dir="$(dirname "$real")"
  base="$(basename "$real")"
  t="$(mktemp -d)"
  mkdir -p "$t/cwd" "$t/file/sub" "$t/rel/sub" "$t/chain/sub" "$t/dir"
  ln -s "$real" "$t/file/sub/$base"
  ln -sr "$real" "$t/rel/sub/$base" 2>/dev/null || echo "note: relative left out (ln -sr not available)"
  ln -s "$t/file/sub/$base" "$t/chain/sub/$base"
  ln -s "$dir" "$t/dir/$(basename "$dir")"
  for how in direct file relative chain dir; do
    case "$how" in
      direct) path="$real" ;;
      file) path="$t/file/sub/$base" ;;
      relative) path="$t/rel/sub/$base" ;;
      chain) path="$t/chain/sub/$base" ;;
      dir) path="$t/dir/$(basename "$dir")/$base" ;;
    esac
    [ -e "$path" ] || continue
    if [ -x "$real" ]; then
      out="$(cd "$t/cwd" && "$path" "$@" 2>&1)"
    else
      out="$(cd "$t/cwd" && bash "$path" "$@" 2>&1)"
    fi
    code=$?
    res="exit=$code last=${out##*$'\n'}"
    echo "$how: $res"
    starts=$((starts + 1))
    if [ "$how" = direct ]; then first="$res"; elif [ "$res" != "$first" ]; then diff=$((diff + 1)); fi
  done
  rm -rf "$t"
  if [ "$diff" -eq 0 ]; then
    echo "link-start: same starts=$starts"
  else
    echo "link-start: DIFFERENT differing=$diff starts=$starts"
    return 1
  fi
}

selftest() {
  local t rc=0 out code
  t="$(mktemp -d)"
  mkdir -p "$t/repo/scripts" "$t/via"
  printf 'marker\n' > "$t/repo/marker"
  # resolving.sh: finds its root through the links -> the same answer on every start
  printf '%s\n' '#!/usr/bin/env bash' \
    'p="${BASH_SOURCE[0]}"' \
    'while [ -L "$p" ]; do d="$(cd -P "$(dirname "$p")" && pwd)"; l="$(readlink "$p")"; case "$l" in /*) p="$l" ;; *) p="$d/$l" ;; esac; done' \
    'r="$(cd -P "$(dirname "$p")/.." && pwd)"' \
    'if [ -f "$r/marker" ]; then echo "root: ok"; else echo "root: wrong"; exit 1; fi' > "$t/repo/scripts/resolving.sh"
  # naive.sh: takes the directory above the path it was started by -> wrong root through every link, exit 1
  printf '%s\n' '#!/usr/bin/env bash' \
    'r="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"' \
    'if [ -f "$r/marker" ]; then echo "root: ok"; else echo "root: wrong"; exit 1; fi' > "$t/repo/scripts/naive.sh"
  # green.sh: the case of issue #29 - the same wrong root, but the program ends with exit 0 whatever it finds; only
  # the last line tells the starts apart
  printf '%s\n' '#!/usr/bin/env bash' \
    'r="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"' \
    'n=0; [ -f "$r/marker" ] && n=1' \
    'echo "checked=$n: ok"' > "$t/repo/scripts/green.sh"
  # args.sh: prints its arguments -> they reach the program on every start
  printf '%s\n' '#!/usr/bin/env bash' 'echo "args: $*"' > "$t/repo/scripts/args.sh"
  chmod +x "$t/repo/scripts/resolving.sh" "$t/repo/scripts/green.sh"

  # 1. a program that resolves the links: same, exit 0
  out="$(probe "$t/repo/scripts/resolving.sh")"; code=$?
  [ "$code" -eq 0 ] || { echo "selftest FAIL: resolving program reported as different:"; printf '%s\n' "$out"; rc=1; }
  case "${out##*$'\n'}" in
    "link-start: same starts="*) ;;
    *) echo "selftest FAIL: want 'link-start: same starts=N', got: ${out##*$'\n'}"; rc=1 ;;
  esac
  printf '%s\n' "$out" | grep -q -x 'dir: exit=0 last=root: ok' || { echo "selftest FAIL: no line for the start through the directory link"; rc=1; }

  # 2. a program that does not (not executable, so it is started with bash): every link start differs, exit 1
  out="$(probe "$t/repo/scripts/naive.sh")"; code=$?
  [ "$code" -eq 1 ] || { echo "selftest FAIL: naive program not reported as different (exit $code)"; rc=1; }
  printf '%s\n' "$out" | grep -q -x 'direct: exit=0 last=root: ok' || { echo "selftest FAIL: naive program wrong on the direct start"; rc=1; }
  printf '%s\n' "$out" | grep -q -x 'file: exit=1 last=root: wrong' || { echo "selftest FAIL: file link start of the naive program not shown as wrong"; rc=1; }
  printf '%s\n' "$out" | grep -q -x 'chain: exit=1 last=root: wrong' || { echo "selftest FAIL: chain start of the naive program not shown as wrong"; rc=1; }
  printf '%s\n' "$out" | grep -q -x 'dir: exit=1 last=root: wrong' || { echo "selftest FAIL: directory link start of the naive program not shown as wrong"; rc=1; }
  case "${out##*$'\n'}" in
    "link-start: DIFFERENT differing="*) ;;
    *) echo "selftest FAIL: want 'link-start: DIFFERENT ...', got: ${out##*$'\n'}"; rc=1 ;;
  esac

  # 3. the same exit code on every start, only the last line differs: still different
  out="$(probe "$t/repo/scripts/green.sh")"; code=$?
  [ "$code" -eq 1 ] || { echo "selftest FAIL: a start that differs only in its last line not reported (exit $code)"; rc=1; }
  printf '%s\n' "$out" | grep -q -x 'file: exit=0 last=checked=0: ok' || { echo "selftest FAIL: green program, file link line missing"; rc=1; }

  # 4. arguments reach the program
  out="$(probe "$t/repo/scripts/args.sh" one "two words")"; code=$?
  [ "$code" -eq 0 ] || { echo "selftest FAIL: args program reported as different"; rc=1; }
  printf '%s\n' "$out" | grep -q -x 'file: exit=0 last=args: one two words' || { echo "selftest FAIL: arguments did not reach the program"; rc=1; }

  # 5. the probe itself, started through a link, measures the same (its own root is resolved)
  ln -s "$SELF" "$t/via/probe.sh"
  out="$(bash "$t/via/probe.sh" "$t/repo/scripts/resolving.sh")"; code=$?
  [ "$code" -eq 0 ] || { echo "selftest FAIL: the probe started through a link gives exit $code"; rc=1; }

  # 6. usage: no program, or a program that is no file -> exit 2
  bash "$SELF" >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL: no argument gives exit $code, want 2"; rc=1; }
  bash "$SELF" "$t/repo/scripts/absent.sh" >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL: a missing program gives exit $code, want 2"; rc=1; }

  rm -rf "$t"
  [ "$rc" -eq 0 ] && echo "selftest ok (6 cases)"
  return "$rc"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$SELF"; exit 0 ;;
  "") echo "usage: link-start-probe.sh PROGRAM [ARG ...] | --selftest" >&2; exit 2 ;;
  -*) echo "link-start-probe.sh: unknown option $1" >&2; exit 2 ;;
esac
[ -f "$1" ] || { echo "link-start-probe.sh: not a file: $1" >&2; exit 2; }
probe "$@"
