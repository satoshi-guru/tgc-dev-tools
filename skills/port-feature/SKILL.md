---
name: port-feature
description: Guided extraction of a feature from game-backend sandbox to main. Never merges — always manually extracts, reviews, and upgrades Gemini's code before applying to main. Run gemini-review first.
---

# Port Feature — game-backend → main

Extract a feature from `hl_game_backend` (Gemini's sandbox) and apply it to `hl_claw_bot` (main bot). Never merge branches — always manually extract and upgrade.

**Core rule**: We do not copy-paste. We read, understand, improve, and apply.

---

## Invoke This Skill When

- User says "port <feature>", "bring over <X> from game-backend", "extract phase N"
- After completing a `/gemini-review` that cleared for porting

---

## Step 1 — Scope the Feature

If `$ARGUMENTS` is provided, use it as the feature name. Otherwise ask:
"Which feature from game-backend should I port? (e.g. 'Phase 17 Chronos', 'Emergency Protocol', 'World Tree')"

Then identify all affected files in `hl_game_backend`:
```bash
cd /home/rootvault/Dokumente/hl_game_backend
git log --oneline -10   # recent commits to identify the feature
git diff HEAD~3 --name-only   # adjust range to bracket the feature
```

---

## Step 2 — Run Gemini Review

If not already done, invoke the gemini-review skill on the target files.
Do NOT proceed past this step if there are P1 blockers — fix them in the ported version, document the fix.

---

## Step 3 — Inventory What to Port

For each file in game-backend that belongs to this feature, record:

| Component | game-backend path | main target path | Action |
|-----------|-------------------|------------------|--------|
| Game logic | `src/game/chronos.py` | `src/game/chronos.py` | Create new |
| API routes | `src/api/game_routes.py` lines N-M | `src/api/game_routes.py` | Append new endpoints |
| DB migration | In `_ensure_tables()` | `src/api/game_routes.py` `_ensure_tables()` | Add new table blocks |
| UI panel | `src/static/game.html` | `src/static/game.html` | Splice into correct tab |
| Tests | `tests/test_<feature>.py` | `tests/test_<feature>.py` | Create new |

**Two DB separation rule**: game.db routes → `src/api/game_routes.py`; isekai routes → `src/api/game_isekai_routes.py`.

---

## Step 4 — Read Source Carefully

Before writing anything, read each source file section:
- Understand the data model (tables, columns, relationships)
- Understand the business logic (not just the code)
- Note any Gemini weaknesses found in Step 2 — plan the upgrade

Do NOT skip this step even if the feature "looks simple".

---

## Step 5 — Apply to Main

Work file by file. For each:

1. **New standalone file** → create it in the correct `src/game/` or `src/api/` path
2. **Additions to existing file** → use Edit; never rewrite the whole file
3. **DB migration** → add new `CREATE TABLE IF NOT EXISTS` blocks inside `_ensure_tables()`; always `IF NOT EXISTS`
4. **API routes** → append after last existing route in the relevant section; preserve route ordering
5. **UI panel** → splice into the correct tab div; match existing tab naming conventions

Apply P1 fixes from the review as you port. Document each fix with a comment: `# fixed: <pattern name from gemini-review>`

---

## Step 6 — Test

```bash
cd /home/rootvault/Dokumente/hl_claw_bot
source .venv/bin/activate
pytest -x -q 2>&1 | tail -20
```

All tests must pass before committing. If a new test file was created in game-backend, port it too.

---

## Step 7 — Commit

```bash
git add <specific files only — never git add -A>
git commit -m "feat(game): port <feature name> — <one-line description>"
```

Commit message format: `feat(game): Port Phase N — <feature> — <what it does>`

Do NOT push without user saying "push this" or "deploy".

---

## Step 8 — Document

Update `BUILDLOG.md` with a session entry:
```
## Session <N> — <date> — Port: <feature>
Files changed: <list>
Tests: <before> → <after> passing
What was ported: <description>
P1 fixes applied: <list of Gemini bugs fixed during port>
```

---

## Guardrails

- Never `git merge game-backend` or cherry-pick — always manual extraction
- Never edit files in `hl_game_backend` — it's Gemini's sandbox, read-only for us
- Never commit broken tests — fix or skip with documented reason
- Never push autonomously — commit+push then wait for explicit go-ahead
- If a feature has >5 files, split into multiple commits by logical chunk
