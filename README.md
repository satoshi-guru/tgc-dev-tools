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
│   ├── session-init/           # Session start from .claude/session-init.yml (worktree, plan, feedback memory)
│   ├── analyze-trade/          # Deep-dive closed trade analysis
│   ├── llmdoc/                 # Fetch library docs locally as LLM-ready markdown
│   └── design-review/          # Design partner: design + pressure-test code BEFORE you build it
├── scripts/
│   ├── gate.sh                 # Offline gate for this repo (not installed) — see "Gate"
│   ├── install-status.sh       # Is a project's .claude in step with this repo? Read-only — see "Installed state"
│   └── readme-listing-check.sh # Does this README list every agent, command, skill and script?
├── .claude/agents/             # Board role files bb-* for this repo's own build lanes (not installed)
└── install.sh                  # One-command install into a project's .claude (destination required)
```

`install.sh` copies only `agents/`, `commands/` and `skills/`. `scripts/` and `.claude/` stay in this repo.

---

## Install

Copy tools into a project's `.claude/` directory. The destination is **required** — there is no default.
A bare `./install.sh` prints the usage and exits 2 without writing anything (until issue #4 it silently
installed into `hl_claw_bot`).

```bash
# Install into hl_claw_bot
./install.sh /home/rootvault/Dokumente/hl_claw_bot/.claude

# Install into hl_game_backend
./install.sh /home/rootvault/Dokumente/hl_game_backend/.claude

# Install into a different project
./install.sh /path/to/your-project/.claude

# Usage text
./install.sh --help
```

What the install does:

- The destination is the `.claude` directory itself; it receives `agents/`, `commands/` and `skills/`.
- Files of the same name in the destination are **overwritten**; a skill's `evals/` folder is not installed.
- `hl_claw_bot` and `hl_game_backend` both list `.claude/` in their `.gitignore`. Installed copies are therefore
  untracked there: they do not show up in `git status`, are not part of a clone, and every checkout or worktree
  of those repos needs its own install. This repo is the only versioned source — edit here, then reinstall.

Installing globally is possible, but read this first:

```bash
./install.sh ~/.claude
```

`~/.claude/skills/` already holds skills of the same name that have **drifted** from this repo (tracked in
issue #3; on 2026-10-03 the `SKILL.md` of `llmdoc`, `start-coding-session` and `session-init` differed from the
global copies). A global install overwrites them with the versions from this repo, which are not always the
newer ones. Compare before you run it.

### Installed state

Because the installed copies are untracked, nothing in `git status` of a target repo shows that it is behind.
`scripts/install-status.sh` is the check. It only reads the destination and compares by name **and** content:

```bash
scripts/install-status.sh /home/rootvault/Dokumente/hl_claw_bot/.claude      # exit 0 in step · 1 behind · 2 usage
scripts/install-status.sh /home/rootvault/Dokumente/hl_game_backend/.claude
scripts/install-status.sh --rehearse /path/to/project/.claude                # what would an install change?
scripts/install-status.sh --selftest
```

One line per tool, then `install-status: in step same=S extra=E` or
`install-status: BEHIND missing=M differs=D same=S extra=E`:

- `SAME` — installed, every file identical.
- `MISSING` — not installed; `install.sh` would add it.
- `DIFFERS` — installed with other content; `install.sh` would **overwrite** it. The differing files are listed with
  the date of the last commit here and the modification date there, so you can see which side is newer before you
  install. Look at the difference with `diff -r skills/<name> <destination>/skills/<name>`.
- `EXTRA` — in the destination but not from this repo (a project's own agents, the board role files `bb-*`);
  `install.sh` leaves it alone.
- `WARN` — a destination skill carries an `evals/` folder; `install.sh` would remove that folder.

`--rehearse` copies the destination's `agents/`, `commands/` and `skills/` into a temp dir, runs `install.sh` into
that copy and prints the status before and after. The real destination is not written.

State measured on 2026-10-03 (issue #6). Nobody has installed since; the gap is still open:

| Destination | Result | Missing | Extra (not from this repo) |
|---|---|---|---|
| `hl_claw_bot/.claude` | `BEHIND missing=3 differs=0 same=9 extra=4` | skills `design-review`, `llmdoc`, `session-init` | agents `bb-bauer`, `bb-pruefer`, `bb-verifikation`; command `start-coding-session.md` |
| `hl_game_backend/.claude` | `BEHIND missing=11 differs=0 same=1 extra=7` | everything except command `rescue-bot` | agents `bb-bauer`, `bb-pruefer`, `bb-verifikation`, `game-builder`, `game-designer`, `game-validator`, `isekai-storyteller` |

`differs=0` in both: every copy that is installed is identical to this repo, so an install would only add files
there and overwrite nothing with other content. Whether `hl_game_backend` should get the full set is an open
decision of the repo owner (issue #6) — this README does not claim that any tool is left out on purpose.
`hl_claw_bot/.claude/commands/start-coding-session.md` does not come from this repo (here `start-coding-session`
is a skill); an install neither updates nor removes it.

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

### `/session-init`
Starts a working session from the project's own config. User-invoked only (`disable-model-invocation: true`).

- Detects whether the cwd is a git worktree and shows branch + last 3 commits
- Reads `.claude/session-init.yml` of the project (`required_reads`, `conditional_reads`, `buildlog_tail`,
  `test_cmd`, `health_checks`); without that file it falls back to `git status` + the tail of `CLAUDE.md`
- On a feature branch reads `SESSION_STATE.<branch-slug>.md` instead of `SESSION_STATE.md`
- Picks the active plan from `~/.claude/plans/`, scoped to the current repo by the plan's `**Repo:**` line
  (so an `hl_game_backend` plan does not seed an `hl_claw_bot` session), and seeds the task list from its open items
- Reads every `feedback_*.md` of the project memory in full, then prints a compact session brief

**When to use**: Start of a session in a project that carries a `.claude/session-init.yml`.

**Drift**: the copy in `~/.claude/skills/session-init/` is newer (2026-09-17: it adds a shortcut through
`~/.claude/scripts/dev/context.py`); the copy in this repo dates from 2026-06-05 and lacks it. Reconciling is issue #3.

---

### `analyze-trade`
Deep-dive analysis of a single closed trade via SSH to VPS.
Queries `memory.db` and DCL candles to explain entry, exit, TP/SL outcome.

Usage: `/analyze-trade <oid>` or `/analyze-trade BTC 14:30`

---

### `/llmdoc`
Fetches the documentation of a library and saves it as LLM-ready markdown under `docs/<slug>/` of the current project.

- Argument: a known alias (`fastapi`, `hyperliquid`, `expo`, …), a raw URL, or `preset:<group>` — groups live in
  `skills/llmdoc/PRESETS.md` and combine with `+` (`/llmdoc preset:hl_game`)
- Chains `/doc-indexer` afterwards to build the token-cheap `COMPACT.md` layer

**When to use**: Before writing config or code against an unfamiliar or recently changed library API, and right
after a first install/build/run attempt fails.

**Drift**: this copy differs from `~/.claude/skills/llmdoc/` (global copy from 2026-09-10); see issue #3 and PR #1.

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

## Gate

`scripts/gate.sh` is the only gate of this repo (there is no build file). It runs offline in a few seconds and is
what the fleet board runs before a PR is merged. Run it before every commit that touches a tool file:

```bash
scripts/gate.sh             # last line "gate: ok" (exit 0) or "gate: FAILED" (exit 1)
scripts/gate.sh --selftest  # proves the checks reject broken fixtures and accept good ones
```

What it checks:

1. `bash -n` over `install.sh` and every `scripts/*.sh`
2. `agents/*.md` and `skills/*/SKILL.md` carry YAML frontmatter with `name` + `description`; `commands/*.md` are non-empty
3. `.claude/agents/*.md` pass `~/.claude/scripts/dev/agent-file-check.py` (skipped with a note when that store is absent)
4. `install.sh` into a temp dir installs every agent, command and skill dir (counts match), and the result is in
   step with the source file by file (`scripts/install-status.sh`)
5. `install.sh` has no default destination (read statically — the gate never runs it without a destination)
6. This README lists every agent, command, skill and script — via `scripts/readme-listing-check.sh`

`scripts/readme-listing-check.sh` can be run on its own. It compares the tree in "What's Inside" and the `###`
headings with `agents/`, `commands/`, `skills/` on disk, in both directions:

```bash
scripts/readme-listing-check.sh             # "MISSING …"/"STALE …" lines, then "readme-listing: ok checks=N" or "FAILED gaps=K"
scripts/readme-listing-check.sh --selftest
```

So a new skill, agent or command needs a tree line **and** a `###` section here, or the gate is red.

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

# 3. Reinstall into each project that uses it (the destination is required)
./install.sh /home/rootvault/Dokumente/hl_claw_bot/.claude
./install.sh /home/rootvault/Dokumente/hl_game_backend/.claude

# 4. Confirm each project is in step (read-only; last line "install-status: in step …", exit 0)
scripts/install-status.sh /home/rootvault/Dokumente/hl_claw_bot/.claude
scripts/install-status.sh /home/rootvault/Dokumente/hl_game_backend/.claude
```

That's the full loop. Run `scripts/gate.sh` before step 2; a new skill, agent or command also needs its tree line
and `###` section in this README (the gate checks it).

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
