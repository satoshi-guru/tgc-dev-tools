# Design Dimensions

The lens to think across — in DESIGN mode to shape the proposal, in REVIEW mode to
find what's wrong. You don't write a paragraph per dimension; you use them so you
don't miss a *class* of problem. Each carries the high-value traps that have actually
bitten this repo — treat every one as a **hypothesis to confirm or clear against the
live source** (see `grounding-protocol.md`), never as a fact to assert from this page.

## 1. Architectural fit
- Does it land where the module map (`CODEBASE_CLAUDE.md`) says it should?
- *Does the thing already exist?* Grep before believing "new" — this repo has shipped
  duplicate commands and parallel signal paths. If it exists, extend or replace it
  deliberately.
- Does it grow a coordination-heavy file when a new module + a small wiring call
  would do? Confirm the file is actually hot right now by reading it / its history.
- Game-layer work: which branch owns it? (`main` vs `game-backend` split — verify in
  `GAME_CLAUDE.md` and the live tree, not from memory.)
- Game-UI backends: does the UI actually call this path? (sidecar vs FastAPI routes —
  trace the call.)

## 2. Coupling & cohesion
- New dependencies justified, or reaching across the codebase? Any import cycle?
- Does each new piece have one job, or is it a grab-bag?
- **The second-order question:** what does this *force* elsewhere? If a change to X
  now requires a change to Y, name that coupling — it's the cost nobody priced.

## 3. State & concurrency
- Any blocking I/O (sync SQLite, network, sleep) on an async event loop? This has
  caused a real freeze here — confirm whether the handler runs on the loop and what
  the house offload pattern is by reading neighbouring handlers.
- Shared mutable state thread-safe given any `to_thread` offload?
- Singletons reused, not re-instantiated? (Find the singleton in source first.)

## 4. Invariant preservation
- The trading/order/risk/signal paths carry invariants that exist because breaking
  them lost money or corrupted state. Don't recite them from memory — when the design
  touches order placement, fills, drawdown, sizing, or signal weights, **read the
  relevant code and the domain doc** (`CODEBASE_CLAUDE.md` "Key invariants",
  `LIQ_SOUL.md`, etc.) and check the design against what's actually there.

## 5. Failure & error handling
- Does failure surface loudly, or silently return a fake success? (Silent-ack stubs
  are a known hazard here — check what the failure path actually returns.)
- Any `try/except` that swallows and continues? Any plan to quiet a warning by
  demoting its log level? (Both are red flags — fix the root cause.)
- New external integration: what happens on auth failure / timeout / partial result?

## 6. Interface design
- Are contracts typed (Pydantic schemas)? Is the signature stable, or will it churn
  on the next feature?
- Is input validated at the boundary?
- Repo-specific gotchas to verify if relevant: game POST routes returning extra
  fields need `response_model=None`; auth-gated endpoints have a header split — read
  the gate to see which tokens it accepts before assuming a caller can reach it.

## 7. Trade-offs & alternatives (the heart of DESIGN mode)
- Never one idea. Two or more genuinely different shapes.
- For each: what it *buys* and what it *costs*. A trade-off with no cost named is a
  sales pitch, not analysis.
- A recommendation, defended, that the user could overrule on purpose.

## 8. Reversibility & blast radius
- If this is wrong, what breaks — and how would anyone notice? (If the answer is
  "you wouldn't, until a player disputes it" / "until liq data goes empty", that's a
  finding.)
- One-way door (schema migration, data format, public contract) or cheap to undo?
  One-way doors get more scrutiny and a rollback note.
- Touches live trading / money? Strictest review.

## 9. Conventions
- "Delete dead code" → investigate intent first (docstrings, git history, the
  call-site count you actually ran); lean implement-not-delete. Mark bad code with a
  `# CODE-NOTE [CN-NNN]` + `CODE_NOTES.md` entry rather than silently removing.
- New script → modular, headered, `--from-vps` flag if it hits VPS data/API/DB.
- New secret storage → encrypted at rest (Fernet pattern exists), not plaintext.
- Config change in an interdependent set → address the siblings too.
- Don't delete reference docs — archive.
