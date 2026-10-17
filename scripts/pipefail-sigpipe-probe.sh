#!/usr/bin/env bash
# pipefail-sigpipe-probe.sh — how often is `printf '%s\n' "$text" | grep -q PATTERN` false under pipefail, when it matches?
#
# What it does: measures the cause of issue #63. Under `set -o pipefail` a pipeline is false when any part of it
# is. Bash writes the output of its printf builtin line by line (stdout is line buffered), so in
#     printf '%s\n' "$text" | grep -q PATTERN
# grep can find PATTERN in the first line and exit while printf still has lines to write; the next write then
# gets SIGPIPE, printf's side ends with 141, and the pipeline is false although PATTERN is there. How often that
# happens depends on how the two processes are scheduled: rarely on an idle machine, more often under load. The
# probe runs that pipeline (form "pipe") and the same test with the text as a here-string (form "herestring",
# `grep -q PATTERN <<< "$text"`, one process, no pipe) N times each over a text of L lines whose first line
# matches, and counts the false results and the exit codes behind them.
# Usage:   scripts/pipefail-sigpipe-probe.sh [--runs N] [--lines L]   # defaults: 2000 runs, 3 lines
#          scripts/pipefail-sigpipe-probe.sh --selftest               # 4 cases
#          scripts/pipefail-sigpipe-probe.sh --help                   # this header
# Output:  "pipe: runs=N false=F codes=C" and "herestring: runs=N false=F codes=C" (C = the exit codes of the false
#          runs with their counts, "-" when there was none), then the last line
#          "pipefail-sigpipe: runs=N lines=L pipe_false=F herestring_false=H"
# Exit:    0 the readout was made, whatever it says · 1 the selftest found a difference · 2 usage
set -uo pipefail

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }

# make_text L — L lines; the first one is "name: a", the others "line N"
make_text() {
  local i text="name: a"
  i=2
  while [ "$i" -le "$1" ]; do text="$text"$'\n'"line $i"; i=$((i + 1)); done
  printf '%s' "$text"
}

# measure FORM RUNS TEXT — prints "FORM: runs=N false=F codes=C"; sets LAST_FALSE to F
measure() {
  local form="$1" runs="$2" text="$3" i code bad=0 codes=""
  declare -A seen=()
  i=0
  while [ "$i" -lt "$runs" ]; do
    if [ "$form" = pipe ]; then
      printf '%s\n' "$text" | grep -q '^name:'
      code=$?
    else
      grep -q '^name:' <<< "$text"
      code=$?
    fi
    if [ "$code" -ne 0 ]; then
      bad=$((bad + 1))
      seen[$code]=$(( ${seen[$code]:-0} + 1 ))
    fi
    i=$((i + 1))
  done
  for code in "${!seen[@]}"; do codes="$codes${codes:+,}$code:${seen[$code]}"; done
  echo "$form: runs=$runs false=$bad codes=${codes:--}"
  LAST_FALSE=$bad
}

readout() {
  local runs="$1" lines="$2" text pf hf
  text="$(make_text "$lines")"
  measure pipe "$runs" "$text"; pf=$LAST_FALSE
  measure herestring "$runs" "$text"; hf=$LAST_FALSE
  echo "pipefail-sigpipe: runs=$runs lines=$lines pipe_false=$pf herestring_false=$hf"
}

selftest() {
  local rc=0 out
  # the text: 3 lines, the first matches
  [ "$(make_text 3)" = $'name: a\nline 2\nline 3' ] || { echo "selftest FAIL: make_text 3"; rc=1; }
  # the here-string form is never false on a matching text (the fix of issue #63 rests on that)
  out="$(measure herestring 300 "$(make_text 200)")"
  [ "$out" = "herestring: runs=300 false=0 codes=-" ] || { echo "selftest FAIL: herestring form false on a matching text: $out"; rc=1; }
  # the readout carries both forms and the last line in the documented shape
  out="$(readout 5 3)"
  grep <<< "${out##*$'\n'}" -q -E '^pipefail-sigpipe: runs=5 lines=3 pipe_false=[0-9]+ herestring_false=0$' || { echo "selftest FAIL: last line: $out"; rc=1; }
  # usage: a bad --runs value is refused with exit 2
  "${BASH_SOURCE[0]}" --runs x >/dev/null 2>&1
  [ $? -eq 2 ] || { echo "selftest FAIL: --runs x not refused with exit 2"; rc=1; }
  if [ "$rc" -eq 0 ]; then echo "selftest ok"; else echo "selftest FAILED"; fi
  return "$rc"
}

runs=2000 lines=3
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) selftest; exit $? ;;
    -h|--help) usage; exit 0 ;;
    --runs) runs="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --lines) lines="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$runs$lines" in *[!0-9]*|"") echo "--runs and --lines take a positive number" >&2; exit 2 ;; esac
[ "$runs" -ge 1 ] && [ "$lines" -ge 1 ] || { echo "--runs and --lines take a positive number" >&2; exit 2; }
readout "$runs" "$lines"
