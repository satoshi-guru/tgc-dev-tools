# Evidence: scripts-gate-sh-readme-listing-check-sh-22 (issue #22)

Time: 2026-10-24 16:09 (`blackboard.py now`) · holder `bauer-1608` · worktree on `f625b18` (origin/main)

## What was done

The scripts of this repo that still had no row in the script store's registry (`~/.claude/scripts/LOOKUP.md`,
`~/.claude/scripts/MANIFEST.md`) were registered with the append-only intake path the user allowed lanes on
2026-10-06 (`script-intake.py add --ref origin/main`, `--repo` = the main checkout). No existing row was changed,
nothing in `~/.claude/scripts` other than the two appended rows per script.

State at claim time, compared with the issue (2026-10-05):

| script | issue #22 | before (16:08) | after (16:09) |
|---|---|---|---|
| `scripts/gate.sh` | FAIL | ok (registered in the meantime) | ok |
| `scripts/readme-listing-check.sh` | FAIL | ok (registered in the meantime) | ok |
| `scripts/skill-drift.sh` | FAIL | **FAIL** [missing: lookup, manifest] | ok |
| `scripts/link-start-probe.sh` | (did not exist yet) | **FAIL** [missing: lookup, manifest] | ok |

`link-start-probe.sh` is not named in the issue, but the issue's done-condition is that `check --all` ends with
`script-intake: ok`, which needs it.

## Measurement

Before:

```
$ ~/.claude/scripts/dev/script-intake.py check --repo . --all; echo "exit=$?"
ok   scripts/board-prompt-check.sh
ok   scripts/branch-after-probe.sh
ok   scripts/gate.sh
ok   scripts/install-status.sh
FAIL scripts/link-start-probe.sh  [missing: lookup, manifest]
ok   scripts/readme-listing-check.sh
ok   scripts/selftest-last-line-probe.sh
FAIL scripts/skill-drift.sh  [missing: lookup, manifest]
script-intake: 2 FAILED
exit=1
```

(The `register with: ...` hint lines are left out.)

Registration:

```
$ script-intake.py add --repo ~/Dokumente/tgc-dev-tools --path scripts/skill-drift.sh --ref origin/main --lang bash ...
ok   LOOKUP += ~/Dokumente/tgc-dev-tools/scripts/skill-drift.sh
ok   MANIFEST += ~/Dokumente/tgc-dev-tools/scripts/skill-drift.sh
exit=0
$ script-intake.py add --repo ~/Dokumente/tgc-dev-tools --path scripts/link-start-probe.sh --ref origin/main --lang bash ...
ok   LOOKUP += ~/Dokumente/tgc-dev-tools/scripts/link-start-probe.sh
ok   MANIFEST += ~/Dokumente/tgc-dev-tools/scripts/link-start-probe.sh
exit=0
```

After:

```
$ ~/.claude/scripts/dev/script-intake.py check --repo . --all; echo "exit=$?"
ok   scripts/board-prompt-check.sh
ok   scripts/branch-after-probe.sh
ok   scripts/gate.sh
ok   scripts/install-status.sh
ok   scripts/link-start-probe.sh
ok   scripts/readme-listing-check.sh
ok   scripts/selftest-last-line-probe.sh
ok   scripts/skill-drift.sh
script-intake: ok
exit=0
$ ~/.claude/scripts/dev/script-intake.py check --repo ~/Dokumente/tgc-dev-tools --all | tail -1
script-intake: ok
```

Gate:

```
$ bash scripts/gate.sh; echo "exit=$?"
gate: ok
exit=0
```

## Not checked

- Why the merge step of PR #19 and PR #20 did not stop on the red intake check (left open in the issue as well).
- That a future script added to `scripts/` gets its row: nothing in `scripts/gate.sh` reads the store (the gate is
  offline and does not read `~/.claude`), so this gap can open again; the protection is the lane's own intake step.
- Not installed into a live project, not run in a fresh Claude Code session (no tool file changed here).
