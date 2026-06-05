# Grounding Protocol

How to load the truth before you design or critique. The goal: every claim you make
about the current code is something you *just confirmed*, with a `file:line` behind
it. This file does not restate architecture — it points you at the maintained docs
that do, and at the live source that is the final word.

## Why this exists

The first version of this skill carried a hand-written invariant snapshot. It went
stale, it was shallow, and it let the skill assert things from the cheat-sheet
instead of reading code — which is exactly how a design review becomes generic
advice that misses the real trap. The repo already maintains better, fresher
knowledge than any snapshot here could. Use it, then verify against source.

## Step 1 — Load the maintained domain docs

This repo keeps dense, current reference docs precisely so you don't re-derive
architecture from source. Read the ones that cover the area you're touching.
`CLAUDE.md`'s "Session Startup" table is the authoritative index; the high-value
entries:

| Doc | Read it when |
|---|---|
| `CODEBASE_CLAUDE.md` | **Always.** Module map, signal flow, agent architecture, key constants, test conventions. |
| `SESSION_STATE.md` (and `SESSION_STATE.<branch>.md`) | **Always.** Current phase, invariants, last sessions, what's in flight. Check the branch-specific one for the branch you're on. |
| `GAME_CLAUDE.md` + `GAME_SOUL.md` | Anything touching the game layer / sidecar / discord bot. |
| `LIQ_CLAUDE.md` + `LIQ_SOUL.md` + `LIQ_SESSION_STATE.md` | Liquidation strategy. |
| `RECTANGLE_CLAUDE.md` + `RECTANGLE_SOUL.md` | Rectangle engine / executor / routes. |
| `INTEL_CLAUDE.md` + `INTEL_SOUL.md` | Intel gateway (`src/intel/`, intel routes, MCP intel tools). |
| `scripts/analysis/SCRIPTS_CLAUDE.md` | The design adds or touches a script. |
| `CODE_NOTES.md` / `CLAUDE_NOTES.md` | The design touches code that may carry a `# CODE-NOTE [CN-NNN]` marker — read the note before changing it. |
| `EVENT_LOOP_OFFLOAD_BACKLOG.md` | Anything async on the sidecar / event-loop adjacent. |

The `*_SOUL.md` docs carry design *philosophy* and "what not to change" — read them
before proposing changes to a parameter or rule in that subsystem, because they
encode decisions that look arbitrary from the code alone.

These docs are maintained but not infallible. When one conflicts with the live
source, **the source wins** — and note the drift so it can be fixed.

## Step 2 — Read the live code the design touches

Docs orient you; they don't substitute for reading the files you're about to reshape.

- **Open the actual file(s)** the design lives in or next to. Read the neighbouring
  code so your sketch matches the real idioms (connection helpers, error handling,
  return shapes, decorators).
- **Trace the seams.** For every symbol the design reuses, deletes, or extends:
  `grep -rn "<symbol>" src/ gamingstudio/` to find definitions, importers, and call
  sites. "Looks unused" is never a conclusion from a single grep on a name — count
  the callers, check the tests, check for dynamic/string imports.
- **Find the existing version.** Before designing anything "new", grep for it. This
  repo has built duplicate commands and parallel signal paths more than once. If a
  thing like it exists, your design is either an extension of it or a justified
  replacement — decide which, with the existing code open.
- **Confirm the current state**, don't recall it. Is this file actually a
  coordination-heavy hot file right now? Does this table actually have that column?
  Is this loop actually running in production? Open it and see.

## Step 3 — Earn every claim

Before you write a sentence asserting something about the current code, ask: *did I
just look at this, and can I cite it?* If yes, cite the `file:line`. If no, either go
look or don't make the claim. This is the whole game — a design built on a
remembered-but-wrong premise is confidently wrong, and that's worse than no review.

## What good grounding looks like (vs not)

- ❌ "agents.py is a hot file, so don't put logic there." (asserted from memory)
- ✅ "`src/agent/agents.py` is the orchestration seam — `run_trading_cycle` at
  agents.py:430 only sequences agents; every signal input is computed in
  `tools.py` (e.g. funding at tools.py:776) and scored in
  `confluence.py:223`. Putting divergence math in `run_trading_cycle` would be the
  only signal computed outside that path." (confirmed in source, cited, and the
  *reason* it's wrong is now concrete)

The second version is the bar. It's not longer because it's padded — it's longer
because it actually looked.
