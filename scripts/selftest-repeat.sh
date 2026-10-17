#!/usr/bin/env bash
# selftest-repeat.sh — does a selftest stay green when it runs many times, alone or beside copies of itself?
#
# What it does: starts COMMAND (default: the gate.sh next to this file with --selftest) N times, P at a time, each
# run with its own log, and counts the green and the red runs. For every red run it prints its number, exit code,
# log path and every line of its log from the first "selftest FAIL:" line on, so a run that fails once in many
# says why. It is the measurement behind issue #63: `scripts/gate.sh --selftest` was red once in 20 runs on the
# same file content ("listed fixture rejected"), and the case had sent the output that names the check to
# /dev/null. Read-only apart from the logs, which stay in one temp directory (named in the last line).
# Usage:   scripts/selftest-repeat.sh [--runs N] [--parallel P] [--cmd 'COMMAND']   # defaults: 10 runs, 1 at a time
#          scripts/selftest-repeat.sh --runs 20 --parallel 4                          # four selftests side by side
#          scripts/selftest-repeat.sh --selftest                                      # 6 cases on stand-in commands
#          scripts/selftest-repeat.sh --help                                          # this header
# Output:  one block per red run "red run=I exit=E log=PATH" plus its lines from the first "selftest FAIL:" on
#          (indented), then the last line "selftest-repeat: runs=N ok=K failed=F parallel=P logs=DIR".
#          COMMAND runs under bash -c with SELFTEST_REPEAT_RUN=I (1..N) in its environment.
#          A run is green when it ends with exit 0 and its log holds no line starting with "selftest FAIL:".
# Exit:    0 every run green · 1 at least one red run · 2 usage
set -uo pipefail

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }

# repeat RUNS PARALLEL COMMAND — the readout described in the header; returns 0 / 1 as the header's exit codes
repeat() {
  local runs="$1" par="$2" cmd="$3" dir i j ok=0 bad=0 code
  dir="$(mktemp -d)"
  i=1
  while [ "$i" -le "$runs" ]; do
    j=0
    while [ "$j" -lt "$par" ] && [ "$i" -le "$runs" ]; do
      ( SELFTEST_REPEAT_RUN="$i" bash -c "$cmd" > "$dir/run-$i.log" 2>&1; echo "$?" > "$dir/run-$i.exit" ) &
      i=$((i + 1))
      j=$((j + 1))
    done
    wait
  done
  i=1
  while [ "$i" -le "$runs" ]; do
    code="$(cat "$dir/run-$i.exit" 2>/dev/null)"
    code="${code:-255}"
    if [ "$code" -eq 0 ] && ! grep -q '^selftest FAIL:' "$dir/run-$i.log"; then
      ok=$((ok + 1))
    else
      bad=$((bad + 1))
      echo "red run=$i exit=$code log=$dir/run-$i.log"
      awk 'f || /^selftest FAIL:/ { f = 1; print "    " $0 }' "$dir/run-$i.log"
    fi
    i=$((i + 1))
  done
  echo "selftest-repeat: runs=$runs ok=$ok failed=$bad parallel=$par logs=$dir"
  [ "$bad" -eq 0 ]
}

selftest() {
  local rc=0 out code
  # green: a command that always passes -> exit 0, no red block
  out="$(repeat 3 2 'echo selftest ok')"; code=$?
  [ "$code" -eq 0 ] || { echo "selftest FAIL: green command, want exit 0, got $code"; rc=1; }
  case "$out" in *"selftest-repeat: runs=3 ok=3 failed=0 parallel=2 logs="*) ;; *) echo "selftest FAIL: green command, wrong last line: $out"; rc=1 ;; esac
  # red by exit code: every run exits 1 -> exit 1, three red blocks
  out="$(repeat 3 3 'exit 1')"; code=$?
  [ "$code" -eq 1 ] || { echo "selftest FAIL: failing command, want exit 1, got $code"; rc=1; }
  [ "$(printf '%s\n' "$out" | grep -c '^red run=[0-9]* exit=1 ')" -eq 3 ] || { echo "selftest FAIL: failing command, want 3 red blocks: $out"; rc=1; }
  # red by a FAIL line with exit 0: counted red, the FAIL line and what follows it are printed indented
  out="$(repeat 1 1 'echo before; echo "selftest FAIL: x rejected:"; echo "    | FAIL: check 6"')"; code=$?
  [ "$code" -eq 1 ] || { echo "selftest FAIL: FAIL line with exit 0, want exit 1, got $code"; rc=1; }
  grep <<< "$out" -q -x '    selftest FAIL: x rejected:' || { echo "selftest FAIL: FAIL line not printed: $out"; rc=1; }
  grep <<< "$out" -q -x '        | FAIL: check 6' || { echo "selftest FAIL: line after the FAIL line not printed: $out"; rc=1; }
  grep <<< "$out" -q 'before' && { echo "selftest FAIL: line before the first FAIL line printed: $out"; rc=1; }
  # one red run of five, by its number: only run 4 fails, side by side with the others
  out="$(repeat 5 5 '[ "$SELFTEST_REPEAT_RUN" != 4 ]')"; code=$?
  [ "$code" -eq 1 ] || { echo "selftest FAIL: flaky command, want exit 1, got $code"; rc=1; }
  case "$out" in *"red run=4 exit=1 "*"selftest-repeat: runs=5 ok=4 failed=1 parallel=5 logs="*) ;; *) echo "selftest FAIL: flaky command, want run 4 red alone: $out"; rc=1 ;; esac
  # runs not a multiple of parallel: 5 runs, 2 at a time -> all 5 run
  out="$(repeat 5 2 'echo selftest ok')"; code=$?
  case "$out" in *"runs=5 ok=5 failed=0 parallel=2 "*) ;; *) echo "selftest FAIL: 5 runs 2 at a time: $out"; rc=1 ;; esac
  # usage: a bad --runs value is refused with exit 2
  "${BASH_SOURCE[0]}" --runs x >/dev/null 2>&1; code=$?
  [ "$code" -eq 2 ] || { echo "selftest FAIL: --runs x, want exit 2, got $code"; rc=1; }
  if [ "$rc" -eq 0 ]; then echo "selftest ok"; else echo "selftest FAILED"; fi
  return "$rc"
}

runs=10 par=1 cmd=""
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) selftest; exit $? ;;
    -h|--help) usage; exit 0 ;;
    --runs) runs="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --parallel) par="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --cmd) cmd="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$runs$par" in *[!0-9]*|"") echo "--runs and --parallel take a positive number" >&2; exit 2 ;; esac
[ "$runs" -ge 1 ] && [ "$par" -ge 1 ] || { echo "--runs and --parallel take a positive number" >&2; exit 2; }
if [ -z "$cmd" ]; then
  gate="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate.sh"
  cmd="'$gate' --selftest"
fi
repeat "$runs" "$par" "$cmd"
