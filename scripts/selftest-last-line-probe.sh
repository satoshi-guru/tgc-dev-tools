#!/usr/bin/env bash
# selftest-last-line-probe.sh — does a program's --selftest end with a fixed last line, green and red? Read-only.
#
# What it does: starts "PROGRAM --selftest" twice and reads the exit code and the last output line (stdout and
# stderr together) of each start. Issue #67: a red run of scripts/gate.sh --selftest ended with a line of the failed
# case's fixture, so "scripts/gate.sh --selftest | tail -1" showed "    | git push" and not the result.
#   plain   as it is
#   broken  with a stand-in for one command (default awk) first in PATH. The stand-in reads nothing, prints nothing
#           and ends with exit 0, so the cases that need that command fail: a red run without a change to PROGRAM
# A run is fixed when it ends with exit 0 and a last line that starts with "selftest ok", or with another exit code
# and a last line that starts with "selftest FAILED".
# The stand-in lives in a temp dir that is removed at the end; nothing is written next to PROGRAM. Only commands
# that read can be stood in for: a program that gets nothing back from mktemp or cp would work on paths it did not
# mean.
# Usage:   scripts/selftest-last-line-probe.sh [--break CMD] PROGRAM   # PROGRAM is run as it is when executable, else with bash
#          scripts/selftest-last-line-probe.sh --selftest              # 9 cases on temp fixtures
# Options: --break CMD  the command the stand-in replaces in the second start: awk (default), grep, sed, diff,
#                       sort, cmp or find
# Output:  "plain: exit=N fail_lines=K last=<last line>" and "broken (CMD): exit=N fail_lines=K last=<last line>"
#          (fail_lines = lines that start with "selftest FAIL:"), then the last line
#          "selftest-last-line: ok runs=2 red=R" or "selftest-last-line: NOT FIXED not_fixed=K runs=2 red=R" or
#          "selftest-last-line: NOT MEASURED runs=2 red=0" (both runs fixed but none red: nothing known about a red run)
# Exit:    0 both runs fixed, at least one of them red · 1 at least one run not fixed · 3 no run was red ·
#          2 usage / PROGRAM is not a file / CMD is not one of the seven
set -uo pipefail

SELF="${BASH_SOURCE[0]}"
BREAKABLE="awk grep sed diff sort cmp find"

# run_fixed EXIT LAST — returns 0 when a run with this exit code and this last line ends the fixed way
run_fixed() {
  if [ "$1" -eq 0 ]; then
    case "$2" in "selftest ok"*) return 0 ;; esac
  else
    case "$2" in "selftest FAILED"*) return 0 ;; esac
  fi
  return 1
}

# probe CMD PROGRAM — prints the lines described under Output; returns 0, 1 or 3 as described under Exit
probe() {
  local cmd="$1" prog="$2" t how out code last line fails bad=0 red=0
  t="$(mktemp -d)"
  mkdir -p "$t/bin"
  printf '%s\n' '#!/bin/sh' 'exit 0' > "$t/bin/$cmd"
  chmod +x "$t/bin/$cmd"
  for how in plain broken; do
    if [ "$how" = plain ]; then
      if [ -x "$prog" ]; then out="$("$prog" --selftest 2>&1)"; else out="$(bash "$prog" --selftest 2>&1)"; fi
      code=$?
    else
      if [ -x "$prog" ]; then out="$(PATH="$t/bin:$PATH" "$prog" --selftest 2>&1)"; else out="$(PATH="$t/bin:$PATH" bash "$prog" --selftest 2>&1)"; fi
      code=$?
    fi
    last="${out##*$'\n'}"
    fails=0
    while IFS= read -r line; do
      case "$line" in "selftest FAIL:"*) fails=$((fails + 1)) ;; esac
    done <<< "$out"
    if [ "$how" = plain ]; then
      echo "plain: exit=$code fail_lines=$fails last=$last"
    else
      echo "broken ($cmd): exit=$code fail_lines=$fails last=$last"
    fi
    [ "$code" -eq 0 ] || red=$((red + 1))
    run_fixed "$code" "$last" || bad=$((bad + 1))
  done
  rm -rf "$t"
  if [ "$bad" -gt 0 ]; then
    echo "selftest-last-line: NOT FIXED not_fixed=$bad runs=2 red=$red"
    return 1
  fi
  if [ "$red" -eq 0 ]; then
    echo "selftest-last-line: NOT MEASURED runs=2 red=0"
    return 3
  fi
  echo "selftest-last-line: ok runs=2 red=$red"
}

# want WHAT CODE WANT_CODE OUT LINE... — selftest helper: the exit code must be WANT_CODE and OUT must be exactly
# the LINEs. Prints both and returns 1 when it does not hold.
want() {
  local what="$1" code="$2" wantcode="$3" out="$4" exp
  shift 4
  exp="$(printf '%s\n' "$@")"
  if [ "$code" -ne "$wantcode" ] || [ "$out" != "$exp" ]; then
    echo "selftest FAIL: $what: want exit $wantcode and"
    printf '%s\n' "$exp" | while IFS= read -r line; do printf '    | %s\n' "$line"; done
    echo "  got exit $code and"
    printf '%s\n' "$out" | while IFS= read -r line; do printf '    | %s\n' "$line"; done
    return 1
  fi
  return 0
}

selftest() {
  local t fails=0 out code
  t="$(mktemp -d)"
  # the fixtures count the fields of "a b" with awk; with the stand-in they get nothing back and the case fails
  local case_awk='[ "$(printf "a b\n" | awk "{print NF}")" = 2 ] || { echo "selftest FAIL: field count"; printf "    | git push\n"; n=1; }'
  # new.sh: a fixed last line for both results
  printf '%s\n' '#!/usr/bin/env bash' 'n=0' "$case_awk" \
    'if [ "$n" -eq 0 ]; then echo "selftest ok"; else echo "selftest FAILED fail_lines=$n"; exit 1; fi' > "$t/new.sh"
  # old.sh: the shape of issue #67 - the last line is printed on a green run only
  printf '%s\n' '#!/usr/bin/env bash' 'n=0' "$case_awk" \
    '[ "$n" -eq 0 ] && echo "selftest ok (1 case)"' 'exit "$n"' > "$t/old.sh"
  # immune.sh: needs no command at all -> green on both starts
  printf '%s\n' '#!/usr/bin/env bash' 'echo "selftest ok (1 case)"' > "$t/immune.sh"
  # zero.sh: names the failure in its last line but ends with exit 0
  printf '%s\n' '#!/usr/bin/env bash' 'n=0' "$case_awk" \
    'if [ "$n" -eq 0 ]; then echo "selftest ok"; else echo "selftest FAILED fail_lines=$n"; fi' > "$t/zero.sh"
  # redboth.sh: red without the stand-in as well, the fixed way; two FAIL lines, one of them not at the line start
  printf '%s\n' '#!/usr/bin/env bash' 'echo "selftest FAIL: one"' 'echo "    | selftest FAIL: quoted"' \
    'echo "selftest FAIL: two"' 'echo "selftest FAILED fail_lines=2"' 'exit 1' > "$t/redboth.sh"
  # grep.sh: its case needs grep and not awk; executable, so it is started as it is
  printf '%s\n' '#!/usr/bin/env bash' 'n=0' \
    'printf "x\n" | grep -q y && { echo "selftest FAIL: grep found y in x"; n=1; }' \
    'if [ "$n" -eq 0 ]; then echo "selftest ok"; else echo "selftest FAILED fail_lines=$n"; exit 1; fi' > "$t/grep.sh"
  chmod +x "$t/grep.sh"

  # 1. fixed for both results: ok, exit 0
  out="$(probe awk "$t/new.sh")"; code=$?
  want "program with a fixed last line" "$code" 0 "$out" \
    'plain: exit=0 fail_lines=0 last=selftest ok' \
    'broken (awk): exit=1 fail_lines=1 last=selftest FAILED fail_lines=1' \
    'selftest-last-line: ok runs=2 red=1' || fails=$((fails + 1))
  # 2. the shape of the issue: the red run ends with a fixture line -> NOT FIXED, exit 1
  out="$(probe awk "$t/old.sh")"; code=$?
  want "program that prints its last line on a green run only" "$code" 1 "$out" \
    'plain: exit=0 fail_lines=0 last=selftest ok (1 case)' \
    'broken (awk): exit=1 fail_lines=1 last=    | git push' \
    'selftest-last-line: NOT FIXED not_fixed=1 runs=2 red=1' || fails=$((fails + 1))
  # 3. no red run: nothing known, exit 3
  out="$(probe awk "$t/immune.sh")"; code=$?
  want "program the stand-in does not turn red" "$code" 3 "$out" \
    'plain: exit=0 fail_lines=0 last=selftest ok (1 case)' \
    'broken (awk): exit=0 fail_lines=0 last=selftest ok (1 case)' \
    'selftest-last-line: NOT MEASURED runs=2 red=0' || fails=$((fails + 1))
  # 4. the last line names the failure but the exit code is 0: not fixed, and not counted as a red run
  out="$(probe awk "$t/zero.sh")"; code=$?
  want "program that fails with exit 0" "$code" 1 "$out" \
    'plain: exit=0 fail_lines=0 last=selftest ok' \
    'broken (awk): exit=0 fail_lines=1 last=selftest FAILED fail_lines=1' \
    'selftest-last-line: NOT FIXED not_fixed=1 runs=2 red=0' || fails=$((fails + 1))
  # 5. red on both starts, the fixed way; only lines that start with "selftest FAIL:" are counted
  out="$(probe awk "$t/redboth.sh")"; code=$?
  want "program that is red on both starts" "$code" 0 "$out" \
    'plain: exit=1 fail_lines=2 last=selftest FAILED fail_lines=2' \
    'broken (awk): exit=1 fail_lines=2 last=selftest FAILED fail_lines=2' \
    'selftest-last-line: ok runs=2 red=2' || fails=$((fails + 1))
  # 6. --break names another command: the program that needs grep is not turned red by awk, but by grep
  out="$(bash "$SELF" "$t/grep.sh")"; code=$?
  want "program that needs grep, awk stood in for" "$code" 3 "$out" \
    'plain: exit=0 fail_lines=0 last=selftest ok' \
    'broken (awk): exit=0 fail_lines=0 last=selftest ok' \
    'selftest-last-line: NOT MEASURED runs=2 red=0' || fails=$((fails + 1))
  out="$(bash "$SELF" --break grep "$t/grep.sh")"; code=$?
  want "program that needs grep, grep stood in for" "$code" 0 "$out" \
    'plain: exit=0 fail_lines=0 last=selftest ok' \
    'broken (grep): exit=1 fail_lines=1 last=selftest FAILED fail_lines=1' \
    'selftest-last-line: ok runs=2 red=1' || fails=$((fails + 1))
  # 7. the stand-in reaches only the program under test: awk still answers here after a probe
  [ "$(printf 'a b\n' | awk '{print NF}')" = 2 ] || { echo "selftest FAIL: awk does not answer after a probe"; fails=$((fails + 1)); }
  # 8. usage: no program, a program that is no file, an unknown option -> exit 2, nothing on stdout
  out="$(bash "$SELF" 2>/dev/null)"; code=$?
  want "no argument" "$code" 2 "$out" '' || fails=$((fails + 1))
  out="$(bash "$SELF" "$t/absent.sh" 2>/dev/null)"; code=$?
  want "a missing program" "$code" 2 "$out" '' || fails=$((fails + 1))
  out="$(bash "$SELF" --brake awk "$t/new.sh" 2>/dev/null)"; code=$?
  want "an unknown option" "$code" 2 "$out" '' || fails=$((fails + 1))
  # 9. a command that writes cannot be stood in for, and --break needs a value -> exit 2, the program is not started
  out="$(bash "$SELF" --break mktemp "$t/new.sh" 2>/dev/null)"; code=$?
  want "--break mktemp" "$code" 2 "$out" '' || fails=$((fails + 1))
  out="$(bash "$SELF" --break 2>/dev/null)"; code=$?
  want "--break without a value" "$code" 2 "$out" '' || fails=$((fails + 1))

  rm -rf "$t"
  if [ "$fails" -eq 0 ]; then
    echo "selftest ok (9 cases)"
    return 0
  fi
  echo "selftest FAILED fail_lines=$fails"
  return 1
}

CMD="awk"
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$SELF"; exit 0 ;;
  --break)
    [ "$#" -ge 2 ] || { echo "selftest-last-line-probe.sh: --break needs a command ($BREAKABLE)" >&2; exit 2; }
    CMD="$2"
    shift 2 ;;
esac
case " $BREAKABLE " in
  *" $CMD "*) ;;
  *) echo "selftest-last-line-probe.sh: cannot stand in for '$CMD' (one of: $BREAKABLE)" >&2; exit 2 ;;
esac
case "${1:-}" in
  "") echo "usage: selftest-last-line-probe.sh [--break CMD] PROGRAM | --selftest" >&2; exit 2 ;;
  -*) echo "selftest-last-line-probe.sh: unknown option $1" >&2; exit 2 ;;
esac
[ -f "$1" ] || { echo "selftest-last-line-probe.sh: not a file: $1" >&2; exit 2; }
probe "$CMD" "$1"
