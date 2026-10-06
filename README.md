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
│   ├── readme-listing-check.sh # Does this README list every agent, command, skill and script?
│   ├── link-start-probe.sh     # Does a program answer the same when started through a symlink? — see "Gate"
│   ├── skill-drift.sh          # Do the skills here still match ~/.claude/skills? — see "Skills that also exist…"
│   └── skill-drift-declared.txt # The deliberate differences skill-drift.sh accepts (one fork, one appendix)
├── .claude/agents/             # Board role files bb-* for this repo's own build lanes (not installed)
└── install.sh                  # One-command install into a project's .claude (destination required)
```

`install.sh` copies only `agents/`, `commands/` and `skills/`. `scripts/` and `.claude/` stay in this repo.

---

## Install

Copy tools into a project's `.claude/` directory. The destination is **required** — there is no default.
A bare `./install.sh` prints the usage and exits 2 without writing anything (until issue #4 it silently
installed into `hl_claw_bot`). The source is always the repo `install.sh` belongs to, also when it is started
through a symlink such as `~/bin/tgc-install` (until issue #35 it took the directory of the link: it stopped with a
`cp` error, or installed that directory's `agents/`, `commands/` and `skills/` if it had any).

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
- Nothing in the destination is removed. An `evals/` folder that a skill in the destination already has is left
  untouched (until issue #8 the install deleted it).
- `hl_claw_bot` and `hl_game_backend` both list `.claude/` in their `.gitignore`. Installed copies are therefore
  untracked there: they do not show up in `git status`, are not part of a clone, and every checkout or worktree
  of those repos needs its own install. This repo is the only versioned source — edit here, then reinstall.

Installing globally is possible, but read this first:

```bash
./install.sh ~/.claude
```

`~/.claude/skills/` already holds four skills of the same name (next section). A global install overwrites them
with the versions from this repo. Since issue #3 that is harmless for `session-init` and `design-review`, but it
would replace the generic `start-coding-session` template of every other project with the hl_claw_bot variant and
append the superseded block to the global `llmdoc/PRESETS.md`. Run `scripts/skill-drift.sh` first and read what it
lists.

### Installed state

Because the installed copies are untracked, nothing in `git status` of a target repo shows that it is behind.
`scripts/install-status.sh` is the check. It only reads the destination and compares by name **and** content:

```bash
scripts/install-status.sh /home/rootvault/Dokumente/hl_claw_bot/.claude      # exit 0 in step · 1 behind · 2 usage
scripts/install-status.sh /home/rootvault/Dokumente/hl_game_backend/.claude
scripts/install-status.sh --rehearse /path/to/project/.claude                # what would an install change?
scripts/install-status.sh --selftest                                         # 8 cases on temp fixtures
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
- `NOTE` — a destination skill carries an `evals/` folder; `install.sh` leaves that folder as it was (until issue #8
  it removed it). Not a gap, not counted.

`--rehearse` copies the destination's `agents/`, `commands/` and `skills/` into a temp dir, runs `install.sh` into
that copy and prints the status before and after. The real destination is not written.

Start the program by its real path: through a symlink it looks for the repo above the link and ends with exit 2
(issue #43, the class of issue #35).

State measured on 2026-10-06 15:35 (read-only, source `main` at `0781454`; issue #6). Both destinations are in step:

| Destination | Result | Exit | Missing | Differs | Extra (not from this repo, left alone) |
|---|---|---|---|---|---|
| `hl_claw_bot/.claude` | `in step same=12 extra=4` | 0 | — | — | agents `bb-bauer`, `bb-pruefer`, `bb-verifikation`; command `start-coding-session.md` |
| `hl_game_backend/.claude` | `in step same=12 extra=7` | 0 | — | — | agents `bb-bauer`, `bb-pruefer`, `bb-verifikation`, `game-builder`, `game-designer`, `game-validator`, `isekai-storyteller` |

Both repos get the full set: 2 agents, 2 commands, 8 skills. That was decided on 2026-10-06 (issue #6); no tool is
left out of either repo on purpose. `install.sh` ran into both destinations that day (the installed files there
carry 15:27).

How the gap closed — the same program against the same two destinations:

| Measured | `hl_claw_bot/.claude` | `hl_game_backend/.claude` |
|---|---|---|
| 2026-10-03 | `BEHIND missing=3 differs=0 same=9 extra=4`, exit 1 | `BEHIND missing=11 differs=0 same=1 extra=7`, exit 1 |
| 2026-10-06 14:26 | `BEHIND missing=3 differs=2 same=7 extra=4`, exit 1 | `BEHIND missing=11 differs=0 same=1 extra=7`, exit 1 |
| 2026-10-06 15:35, after the install | `in step same=12 extra=4`, exit 0 | `in step same=12 extra=7`, exit 0 |

The table is a dated measurement, not a standing fact — run the program for today's state. Every merge here that
changes an installed file puts both destinations behind again until the reinstall (steps 3 and 4 of "Update
Workflow"): the second row shows it, two files (`code-porter`, `/port-feature`, issue #38) had changed here and the
copies in `hl_claw_bot` were from 2026-05-24. Only the main checkouts of the two repos were measured; a worktree of
either repo has its own untracked `.claude` and needs its own install.

Four of the installed skills (`design-review`, `llmdoc`, `session-init`, `start-coding-session`) also exist in
`~/.claude/skills/`. On this machine a session in either repo loads the global copy of those names; the project
copy that the install put there is overridden (next section). `hl_claw_bot/.claude/commands/start-coding-session.md`
does not come from this repo (here `start-coding-session` is a skill); an install neither updates nor removes it.

---

## Skills that also exist in `~/.claude/skills`

Four skills of this repo have a copy of the same name in the global store `~/.claude/skills/`. Claude Code resolves
a name that exists at both levels to the **personal** copy ("enterprise overrides personal, and personal overrides
project" — Claude Code docs, skills). On this machine a session therefore loads the global copy of these four, also
inside a project that this repo was installed into; the copies here are the versioned record and what a machine
without the global store gets.

Which copy is canonical (decided in issue #3, measured on 2026-10-03):

| Skill | Canonical copy | State of the copy in this repo | A change goes |
|-------|----------------|--------------------------------|---------------|
| `llmdoc` | `~/.claude/skills/llmdoc/` — newer (2026-09-10) and the only copy whose fetcher path exists (`llmdocs/crawler.py`; the old repo copy named `llmdocs.py`, which is gone) | `SKILL.md` identical. `PRESETS.md`: lines 1–29 are the global file byte for byte; below them the old repo-only tables are kept as a **superseded appendix**, not active | into the global copy first, then here by pull request |
| `session-init` | `~/.claude/skills/session-init/` — newer (2026-09-17, adds the `context.py` shortcut) | identical | into the global copy first, then here by pull request |
| `start-coding-session` | **Both, for different projects — never synced.** This repo: the hl_claw_bot variant. Global: the generic template for every other project | differs on purpose (78 vs 98 lines), declared as a fork | here for hl_claw_bot specifics; the global template is not this repo's business |
| `design-review` | this repo — the versioned source; the global copy is an install of it | every shared file identical; `README.md` exists only here | here by pull request; the global copy is then updated by hand, never by a board lane |

The other four skills (`git-check`, `gemini-review`, `port-feature`, `analyze-trade`) exist only here.

Measure it — read-only, it never writes to the store or to this repo:

```bash
scripts/skill-drift.sh               # last line "skill-drift: in step same=1 extra=2 fork=1 only-here=4" (exit 0)
scripts/skill-drift.sh llmdoc        # one skill only
scripts/skill-drift.sh --selftest    # 11 cases on temp fixtures
```

- `SAME` every file identical · `EXTRA` everything the store holds is here verbatim, this repo has more ·
  `FORK` differs and is declared · `DRIFT` differs and is **not** declared (exit 1) · `STALE` a declaration that no
  longer holds (exit 1)
- The deliberate differences are data, not memory: `scripts/skill-drift-declared.txt` holds one line per fork or
  appendix with the reason. A new difference that is not declared there turns the readout red.
- The readout is not part of `scripts/gate.sh`: the gate has to give the same answer on every machine and must
  not turn red because a file in `~/.claude` changed. Run it when an item concerns one of the four skills and
  before any global install.

Known consequences, each with its own issue:

- The hl_claw_bot variant of `start-coding-session` is shadowed by the global template of the same name, so
  `/start-coding-session` inside `hl_claw_bot` loads the generic template. It needs its own name (issue #12).
- Four preset groups of the old `PRESETS.md` (`hl_bot`, `x-promo`, `gaming-studio`, `happy-tool`) are not in the
  canonical table and therefore not active (issue #13).
- Pull request #1 (llmdoc sync from 2026-06-07) is superseded: it points the fetcher at
  `Dokumente/llmdocs-publish/`, a directory that no longer exists.

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

**Canonical copy**: this is the hl_claw_bot variant and is kept that way; `~/.claude/skills/start-coding-session/`
is a different skill under the same name (the generic template) and wins the name on this machine — see "Skills
that also exist in `~/.claude/skills`" and issue #12.

---

### `/session-init`
Starts a working session from the project's own config. User-invoked only (`disable-model-invocation: true`).

- Shortcut first: when `~/.claude/scripts/dev/context.py` exists it runs that program, prints its output as the
  brief and stops; the steps below are the fallback
- Detects whether the cwd is a git worktree and shows branch + last 3 commits
- Reads `.claude/session-init.yml` of the project (`required_reads`, `conditional_reads`, `buildlog_tail`,
  `test_cmd`, `health_checks`); without that file it falls back to `git status` + the tail of `CLAUDE.md`
- On a feature branch reads `SESSION_STATE.<branch-slug>.md` instead of `SESSION_STATE.md`
- Picks the active plan from `~/.claude/plans/`, scoped to the current repo by the plan's `**Repo:**` line
  (so an `hl_game_backend` plan does not seed an `hl_claw_bot` session), and seeds the task list from its open items
- Reads every `feedback_*.md` of the project memory in full, then prints a compact session brief

**When to use**: Start of a session in a project that carries a `.claude/session-init.yml`.

**Canonical copy**: `~/.claude/skills/session-init/`. The copy in this repo is identical to it since issue #3
(before, it dated from 2026-06-05 and lacked the `context.py` shortcut of 2026-09-17).

---

### `analyze-trade`
Deep-dive analysis of a single closed trade via SSH to VPS.
Queries `memory.db` and DCL candles to explain entry, exit, TP/SL outcome.

Usage: `/analyze-trade <oid>` or `/analyze-trade BTC 14:30`

---

### `/llmdoc`
Fetches the documentation of a library and saves it as LLM-ready markdown in the global doc store
`~/.llmdocs/docs/<slug>/`, shared by every repo — never into the `docs/` folder of the current project.

- Argument: an engine preset (`discord`, `hyperliquid`, `hypedexer`, `openai`, `anthropic`), a known alias
  (`fastapi`, `expo`, …), a raw URL, or `preset:<group>` — groups live in the table at the top of
  `skills/llmdoc/PRESETS.md` and combine with `+` (`/llmdoc preset:hl_game`, `/llmdoc preset:hl_claw`)
- Runs the fetcher `Dokumente/llmdocs/crawler.py` with `--archive-existing`, so a re-fetch keeps the old copy
- Chains `/doc-indexer` afterwards to build the token-cheap `COMPACT.md` layer, then refreshes the store manifest

**When to use**: Before writing config or code against an unfamiliar or recently changed library API, and right
after a first install/build/run attempt fails.

**Canonical copy**: `~/.claude/skills/llmdoc/` (2026-09-10). Since issue #3 `SKILL.md` here is identical to it,
and `PRESETS.md` is the global file followed by a superseded appendix (the old repo-only tables — not active,
issue #13). PR #1 is superseded by that sync.

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

**Canonical copy**: this repo. `~/.claude/skills/design-review/` is identical in every shared file; the guide
`README.md` exists only here.

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

The gate checks the repo its own file belongs to, wherever it is started from and also when it is started through
a symlink to `scripts/gate.sh` or to `scripts/` (issue #29 — before, a link made it check the directory above the
link, and it ended with `gate: ok` there). Before any numbered check it makes sure that this root is a checkout of
this repo: a root without `install.sh` or without `README.md` is rejected with
`FAIL: not a checkout of this repo: no <file> in <root>` and nothing else is checked or run in it. So a deleted
`README.md` turns the gate red; it no longer skips checks 6 and 7.

What it checks:

1. `bash -n` over `install.sh` and every `scripts/*.sh`
2. `agents/*.md` and `skills/*/SKILL.md` carry YAML frontmatter with `name` + `description`; `commands/*.md` are non-empty
3. `.claude/agents/*.md` pass `~/.claude/scripts/dev/agent-file-check.py` (skipped with a note when that store is
   absent). The checker looks up the paths an agent file names in its working directory, so the gate starts it in
   the repo root — the result is the same wherever the gate itself is started from (issue #21)
4. `install.sh` into a temp dir installs every agent, command and skill dir (counts match), copies every entry of
   a skill (hidden ones too) except its `evals/`, and leaves an `evals/` folder the destination already had as it was.
   The fresh install is also in step with the source file by file, agents and commands included
   (`scripts/install-status.sh`, see "Installed state")
5. `install.sh` has no default destination (read statically — the gate never runs it without a destination)
6. This README lists every agent, command, skill and script — via `scripts/readme-listing-check.sh`
7. This README carries no `git push` command whose target is `main` (issues #16, #18) — one
   `FAIL: README.md:<line>: …` per offending command, at the line where it starts. Rejected: the pushed ref or the
   refspec target is the whole word `main` (`origin main`, `-u origin main`, `HEAD:main`, `feat/x:main`), also when
   the command is wrapped with a backslash or carries options between `git` and `push` (`-C dir`, `-c k=v`);
   the options `--all`, `--mirror` and `--branches`, whatever the remote; and, inside one code block, a push
   without a ref (or of `HEAD`) after a switch or checkout to `main`. Accepted: a push of a branch
   (`git push -u origin feat/x`, also `maintenance` or `feat/main-menu`), a switch to `main` that is followed by a
   pull and no push (step 3 of "Update Workflow"), and prose without the command. The check reads the command, not
   the sentence around it: a quoted push to `main` is rejected even after a "never", so describe the rule in words
   instead. What it still does not see is listed in the comment above `readme_push_main` in `scripts/gate.sh`

`scripts/readme-listing-check.sh` can be run on its own. It compares the tree in "What's Inside" and the `###`
headings with `agents/`, `commands/`, `skills/` on disk, in both directions:

```bash
scripts/readme-listing-check.sh             # "MISSING …"/"STALE …" lines, then "readme-listing: ok checks=N" or "FAILED gaps=K"
scripts/readme-listing-check.sh --selftest   # 6 cases on temp fixtures
```

So a new skill, agent or command needs a tree line **and** a `###` section here, or the gate is red.

`scripts/link-start-probe.sh` measures whether a program gives the same answer when it is started through a
symlink. It starts the program five ways in an empty temp directory — by its path, through a link to the file
(absolute target, relative target, a link to that link) and through a link to its directory — and compares the
last output line and the exit code. Read-only; the links live in a temp dir.

```bash
scripts/link-start-probe.sh scripts/gate.sh   # five "<how>: exit=N last=…" lines, then "link-start: same starts=5" (exit 0) or "link-start: DIFFERENT differing=K starts=5" (exit 1)
scripts/link-start-probe.sh --selftest        # 6 cases on temp fixtures
```

It is not a gate check (the gate's own selftest starts the gate through links). `scripts/gate.sh` gives the same
answer on all five starts since issue #29; `scripts/readme-listing-check.sh`, `scripts/skill-drift.sh` and
`install.sh` since issue #35 (before, started through a link they looked for the repo above the link: exit 1 /
exit 2 / a `cp` error on a good repo, and the answer or the files of another tree when the link sat inside one).
Each of the three starts itself through links in a selftest: the first two in their own `--selftest`, `install.sh`
in `scripts/gate.sh --selftest`. `scripts/install-status.sh` does not give the same answer yet (issue #43) — start
that one by its real path.

`scripts/skill-drift.sh` is deliberately **not** a gate check (it reads `~/.claude/skills`, which differs per
machine and changes without a commit here); see "Skills that also exist in `~/.claude/skills`".

---

## Update Workflow

When you improve a skill or agent, the change reaches `main` through a branch, the gate and a pull request —
never by a push to `main`:

```bash
# 1. Start a branch from origin/main, then edit the source file in tgc-dev-tools
git fetch origin
git switch -c feat/gemini-review-pattern-n --no-track origin/main
vim skills/gemini-review/SKILL.md

# 2. Gate, commit, push the branch, open a pull request against main
scripts/gate.sh             # last line must be "gate: ok" (exit 0); fix and re-run on "gate: FAILED"
git add skills/gemini-review/SKILL.md
git commit -m "feat(gemini-review): add pattern N — <description>"
git push -u origin feat/gemini-review-pattern-n
# PR body: what changed, the gate output, and "Closes #N" when there is an issue
gh pr create --base main --head feat/gemini-review-pattern-n

# 3. After the pull request is merged: reinstall from the merged main into each project that uses it
#    (the destination is required)
git switch main && git pull --ff-only origin main
./install.sh /home/rootvault/Dokumente/hl_claw_bot/.claude
./install.sh /home/rootvault/Dokumente/hl_game_backend/.claude

# 4. Confirm each project is in step (read-only; last line "install-status: in step …", exit 0)
scripts/install-status.sh /home/rootvault/Dokumente/hl_claw_bot/.claude
scripts/install-status.sh /home/rootvault/Dokumente/hl_game_backend/.claude
```

That's the full loop. `main` changes only through a merged pull request: the branch is pushed, `main` is not, and
a board lane (`.claude/agents/bb-*.md`) never merges its own pull request. Step 3 waits for the merge because an
install from an unmerged branch puts files into the projects that `main` does not have. A new skill, agent or
command also needs its tree line and `###` section in this README (the gate checks it).

---

## Development Stack Context

| Repo | Path | Role |
|------|------|------|
| hl_claw_bot | `/home/rootvault/Dokumente/hl_claw_bot` | Production trading bot + game API |
| hl_game_backend | `/home/rootvault/Dokumente/hl_game_backend` | Game feature sandbox (Gemini) |

**Key rules enforced by these tools:**
All four are about work in `hl_claw_bot` and `hl_game_backend`, not about this repo: work on tgc-dev-tools itself
pushes its work branch and goes through a pull request (see "Update Workflow").
- Never merge game-backend → main: a feature moves from `hl_game_backend` to `hl_claw_bot` by manual extraction only.
  `hl_game_backend` is read-only for `code-porter` — the agent never edits, commits or pushes there.
- Never bring `hl_claw_bot` code to the VPS with `scp` — it gets there only as a commit that is pushed and then
  deployed. This rule excludes `scp` as a transport; it does not itself allow a push (that is the next bullet).
- In `hl_claw_bot` and `hl_game_backend`: never push without explicit user instruction — "push this" or "deploy"
  (`code-porter`, `/port-feature`).
- Gemini's code in `hl_game_backend` is always a draft — review and upgrade it before porting to `hl_claw_bot`
