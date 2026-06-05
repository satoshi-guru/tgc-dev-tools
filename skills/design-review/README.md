# design-review

A principal-engineer **design partner** for the hl_claw_bot / hl_game_backend
codebase. It works on the *shape* of code **before it's written** — either designing
it with you or pressure-testing a design you bring it — always grounded in the live
source, citing `file:line`, never reasoning from memory.

This README is the overview. The operating instructions Claude follows live in
`SKILL.md`; this file explains what the skill is, when it fires, and what it produces.

---

## When it triggers

Claude reaches for this skill automatically when you're deciding *how to build*
something that doesn't exist yet. Phrases that fire it:

- "Help me design…", "what's the cleanest way to add…", "where should this live?",
  "how should I structure…", "I need an architecture for…"  → **DESIGN mode**
- "Review my approach", "is this the right shape?", "poke holes in this before I
  build it", "pressure-test this plan"  → **REVIEW mode**
- Also before implementing any non-trivial plan — to catch structural problems while
  they're still a conversation, not a 400-line diff.

You can also invoke it explicitly: `/design-review`.

**It is NOT** `/code-review` (that reviews an existing diff for bugs) and **not**
brainstorming (that explores product requirements). This skill is about the
*architecture of code you're about to write*.

---

## The two modes

| Mode | You have… | It produces… |
|------|-----------|--------------|
| **DESIGN** | a problem, no chosen shape | 2+ real architectures, each with an interface sketch and honest costs, and a defended recommendation |
| **REVIEW** | a proposed shape | a verdict + severity-ordered concerns (each with why-it-matters + a concrete fix) |

Both modes do the same two things that make the output trustworthy:
1. **Ground in live code first** — read the maintained docs (`CODEBASE_CLAUDE.md`,
   `GAME_CLAUDE.md`, `*_SOUL.md`, `CODE_NOTES.md`, …) and the actual files, then cite
   `file:line` for every claim. No memory, no stale cheat-sheet.
2. **Hit the quality bar** — real code/interface sketches (not prose), options with
   real *costs*, and the second-order effects a mid-level engineer would miss.

You also pick the **weight**: a quick one-shot pass for a small question, or a deep
multi-turn design session for a real architecture.

---

## What you get

A short doc (skimmable in ~2 minutes) saved to `design-reviews/<slug>.md` at the repo
root by default — or delivered inline for a quick pass. DESIGN mode uses the proposal
template; REVIEW mode uses the review template. Both end with a **recommended next
step**, usually a handoff to `superpowers:writing-plans` to turn the agreed design
into an implementation plan.

---

## Where it fits in the workflow

```
idea ──▶ design-review ──▶ writing-plans ──▶ implementation ──▶ /code-review
        (right shape?)     (the steps)        (the code)        (bugs in diff)
```

Use it at the **front** of a piece of work, or whenever you're about to commit to an
approach. It saves the expensive class of mistake here: designs that fight the
architecture (logic in a hot file, blocking I/O on the event loop, a duplicate of
something that already exists, a broken trading invariant).

---

## Files

```
design-review/
├── SKILL.md                              # operating instructions (what Claude follows)
├── README.md                             # this overview
├── references/
│   ├── grounding-protocol.md             # how to load truth: maintained docs + live code, cite file:line
│   └── design-dimensions.md              # the review lenses + repo traps to verify against source
├── assets/
│   ├── design-proposal-template.md       # DESIGN-mode output
│   └── design-review-template.md         # REVIEW-mode output
└── evals/
    └── evals.json                        # test prompts + assertions used to verify the skill
```

---

## Relationship to the other tgc-dev-tools

- **`/gemini-review`** — quality gate for *already-written* Gemini code (9 known bug
  patterns). Use this for the pile of open Gemini branches, not design-review.
- **`/port-feature`** — extract good work from `hl_game_backend` → `hl_claw_bot`.
- **design-review** — for code that *doesn't exist yet*. It can pressure-test the
  *architecture* a Gemini branch represents before you decide to port it, but the
  primary triage tools for existing branches are the two above.
