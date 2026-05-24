---
name: start-coding-session
description: Start a structured coding session for hl_claw_bot. Loads context docs, sets up the coding cycle, and asks for the task. Use at the start of any implementation session.
---

# Start Coding Session — hl_claw_bot

## Invoke This Skill When
- User says "start session", "let's code", "begin session", "new session"
- User describes a feature, fix, or refactor without prior context loaded
- After a /clear or compaction event and work needs to resume

## What This Skill Does

Runs the Phase 0–1 context load from `CODING_CYCLE.md`, then asks one focused question before any code is written.

---

## Step 1 — Load Context

Read these files in order (stop early if task scope is clear):

1. `SESSION_STATE.md` — current phase, test count, open plans, invariants
2. `CODEBASE_CLAUDE.md` — module map and signal flow (hot files table only if task is unclear)
3. If task mentions liq → `LIQ_SESSION_STATE.md`
4. If task mentions intel → `INTEL_CLAUDE.md §1-2`
5. If task mentions rectangle → `RECTANGLE_CLAUDE.md §1-2`

Do NOT read full source files at this stage.

---

## Step 2 — Confirm the Task

After loading context, respond with exactly this format:

```
Session context loaded. Current phase: <from SESSION_STATE.md>
Tests passing: <count from SESSION_STATE.md>

Ready to work. What's the task?
```

Then wait for the user's task description before doing anything else.

---

## Step 3 — Task Intake (before touching any file)

Once the task is given, answer these four questions out loud before writing code:

1. **Files affected:** <list specific files and functions>
2. **Invariants at risk:** <which ones from SESSION_STATE.md apply — or "none">
3. **Test strategy:** <existing test file / new test / manual>
4. **Breaking change?** yes/no — if yes, describe migration

---

## Step 4 — Follow CODING_CYCLE.md

Execute phases 2–7 from `CODING_CYCLE.md`:

- Phase 2: Implement (one logical change, no hardcoded constants)
- Phase 3: `pytest` — all tests must pass before commit
- Phase 4: `ruff check src/ tests/`
- Phase 5: Update BUILDLOG.md + SESSION_STATE.md
- Phase 6: Commit with type-scoped message, push
- Phase 7: Stop — never deploy without explicit instruction

---

## Guardrails

- Never skip the invariant checklist at Phase 6
- Never `git add -A` — always add specific files
- Never run `deploy.sh` without the user saying "deploy this"
- Never edit files directly on the VPS — commit + push + deploy only
- If VPS branch is not `main` before deploying — ask first
