# tgc-dev-tools

Claude Code workflow tools for the TradingGate Chronicles development stack.
Skills, agents, and commands that automate the recurring hl_claw_bot + hl_game_backend development loop.

---

## What's Inside

```
tgc-dev-tools/
├── agents/
│   ├── code-porter.md          # Feature porting specialist (game-backend → main)
│   └── discord-dev.md          # Discord bot development specialist
├── commands/
│   ├── fan-out-audit.md        # Mass parallel file audit (fan-out pattern)
│   └── rescue-bot.md           # Emergency bot rescue via VPS SSH
├── skills/
│   ├── git-check/              # Pre-work git hygiene for both repos
│   ├── gemini-review/          # Quality gate before porting Gemini's code
│   ├── port-feature/           # Guided feature extraction game-backend → main
│   ├── start-coding-session/   # Session context loader + task intake
│   ├── analyze-trade/          # Deep-dive closed trade analysis
│   ├── llmdoc/                 # Fetch library docs locally as LLM-ready markdown
│   └── design-review/          # Design partner: design + pressure-test code BEFORE you build it
└── install.sh                  # One-command install into any project
```

---

## Install

Copy tools into a project's `.claude/` directory:

```bash
# Install into hl_claw_bot (default)
./install.sh

# Install into a different project
./install.sh /path/to/your-project/.claude
```

Or install globally (available in all projects):

```bash
./install.sh ~/.claude
```

---

## Skills

### `/git-check`
Pre-work git hygiene for the two-repo setup.
- Fetches both `hl_claw_bot` and `hl_game_backend` from origin
- Reports branch vs origin state (ahead/behind)
- Flags uncommitted changes in hot files
- Lists open feature branches with age

**When to use**: Start of every session, before pushing.

---

### `/gemini-review`
Quality gate before porting any Gemini-authored code.

Checks 9 known failure patterns:
1. **P1** Silent HTTP error eating (`await r.json()` without status check)
2. **P1** Nonexistent backend routes (paths that don't exist in game_routes.py)
3. **P1** Wrong discord.py method signatures
4. **P1** Missing access control guards
5. **P1** Fake success callbacks (show "Done" without calling backend)
6. **P2** Wrong response field names
7. **P2** `asyncio.sleep()` inside event handlers
8. **P2** Hardcoded data that should come from backend
9. **P3** Bare except / no logging

Produces a P1/P2/P3 report. P1 count > 0 = block, fix before porting.

**When to use**: Before any `/port-feature` run.

---

### `/port-feature`
Guided feature extraction from `hl_game_backend` → `hl_claw_bot`.

Steps:
1. Scope the feature (git log, changed files)
2. Run `/gemini-review`
3. Inventory all components (modules, routes, DB migrations, UI, tests)
4. Read source carefully — understand, don't just copy
5. Apply to main with upgrades (fix P1/P2 during port)
6. Run `pytest`
7. Commit specific files
8. Update BUILDLOG.md

**Core rule**: Never merge. Never copy-paste. Always upgrade.

---

### `/start-coding-session`
Loads session context and confirms the task before any code is written.

Reads: `SESSION_STATE.md` → `CODEBASE_CLAUDE.md` → module-specific docs (if needed)

Outputs: current phase, test count, then waits for the task.

**When to use**: Start of every implementation session.

---

### `analyze-trade`
Deep-dive analysis of a single closed trade via SSH to VPS.
Queries `memory.db` and DCL candles to explain entry, exit, TP/SL outcome.

Usage: `/analyze-trade <oid>` or `/analyze-trade BTC 14:30`

---

### `/design-review`
A principal-engineer **design partner** for code that *doesn't exist yet*. Two modes:

- **DESIGN** — "help me design X / where should this live / what's the cleanest way
  to add Y" → proposes 2+ architectures with real code/interface sketches, honest
  trade-offs, and a defended recommendation.
- **REVIEW** — "is this the right shape / pressure-test this before I build it" →
  verdict + severity-ordered concerns, each with why-it-matters and a concrete fix.

Both modes **ground in the live source** (reads the maintained `*_CLAUDE.md` /
`*_SOUL.md` docs + the actual files, cites `file:line`, never reasons from memory)
and surface the second-order effects — broken invariants, hidden coupling, blocking
I/O on the event loop, duplicate features. Output is a short doc saved to
`design-reviews/`, ending in a handoff to `/writing-plans`.

**When to use**: at the *front* of any new feature/refactor, before writing code, or
to pressure-test an approach (including a Gemini branch's architecture) before
committing to it. It is the design counterpart to `/code-review` (which reviews an
existing diff). See `skills/design-review/README.md` for the full guide.

---

## Agents

### `code-porter`
Specialist subagent for feature porting. Knows:
- Both repo paths and the no-merge rule
- Two-DB architecture (game.db vs game_isekai.db)
- All 9 Gemini weakness patterns — fixes them while porting
- Never edits game-backend, never pushes autonomously

Invoke when porting any game feature: `use the code-porter agent to port <feature>`

---

### `discord-dev`
Discord application specialist for TradingGate Chronicles.
Knows discord.py 2.x, Cog architecture, app_commands, gateway intents.
Always reads local docs before coding (`gamingstudio/discord_bot/docs/`).

---

## Commands

### `/fan-out-audit`
Mass parallel code audit. Spawns one agent per file batch, each writing findings to its own file. Use when you need to audit 50-500 files in one pass.

Usage: `/fan-out-audit find refactoring opportunities`

### `/rescue-bot`
Emergency VPS rescue sequence. Closes all positions, resets drawdown peak, restores risk params.

---

## Update Workflow

When you improve a skill or agent:

```bash
# 1. Edit the source file in tgc-dev-tools
vim skills/gemini-review/SKILL.md

# 2. Commit and push
git add skills/gemini-review/SKILL.md
git commit -m "feat(gemini-review): add pattern N — <description>"
git push origin main

# 3. Reinstall into the project
./install.sh /home/rootvault/Dokumente/hl_claw_bot/.claude
```

That's the full loop. Three commands to update any tool everywhere.

---

## Development Stack Context

| Repo | Path | Role |
|------|------|------|
| hl_claw_bot | `/home/rootvault/Dokumente/hl_claw_bot` | Production trading bot + game API |
| hl_game_backend | `/home/rootvault/Dokumente/hl_game_backend` | Game feature sandbox (Gemini) |

**Key rules enforced by these tools:**
- Never merge game-backend → main (manual extraction only)
- Never scp — commit+push+deploy only
- Never push without explicit user instruction
- Gemini's code is always a draft — review and upgrade before porting
