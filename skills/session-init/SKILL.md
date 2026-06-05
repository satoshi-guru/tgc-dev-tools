---
name: session-init
description: Start a working session — detects worktree, reads project override config, loads session docs, runs test baseline, seeds task list from active plan.
disable-model-invocation: true
allowed-tools: Read Bash Glob Grep TaskCreate TaskUpdate
---

You are starting a new working session. Follow these steps in order.

### Step 1 — Detect context

Run these silently:

!`git rev-parse --show-toplevel 2>/dev/null && echo "GIT_ROOT_OK" || echo "NOT_A_GIT_REPO"`
!`git rev-parse --git-dir 2>/dev/null`
!`git rev-parse --git-common-dir 2>/dev/null`
!`git branch --show-current 2>/dev/null`
!`git log --oneline -3 2>/dev/null`

If `git-dir` != `git-common-dir`, you are inside a **worktree**. Note the worktree path for Step 3.

### Step 2 — Find project override

!`cat .claude/session-init.yml 2>/dev/null || echo "NO_OVERRIDE"`

If `NO_OVERRIDE`: use **generic fallback** (Step 4b). Otherwise parse the YAML and use **project override** (Step 4a).

### Step 3 — Find active plan file

`~/.claude/plans/` is shared by every project on this machine, so the listing below is
**scoped to the current repo**: it keeps plans whose `**Repo:**` line names the current
working dir (worktree-aware via `git rev-parse --show-toplevel`) plus plans with no `Repo:`
line, and drops plans tagged for a *different* repo. This prevents e.g. `hl_game_backend`
game plans from seeding an `hl_claw_bot` bot session (or vice-versa).

!`repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"); for f in $(ls -t ~/.claude/plans/*.md 2>/dev/null); do rl=$(grep -m1 -iE '^(\*\*)?Repo:' "$f" 2>/dev/null); if [ -z "$rl" ] || printf '%s\n' "$rl" | grep -qi "$repo"; then echo "$f"; fi; done | head -3`

If inside a worktree: also check for a plan file in the worktree root. Report which plan file is active (most recently modified).

If a plan file is found: read it and extract any open tasks / checklist items to seed the task list.

### Step 4a — Project override (session-init.yml found)

For each file in `required_reads`: read the file fully.
For each entry in `conditional_reads`: read it if the condition matches the user's stated intent or recent git changes.
If `buildlog_tail` is set: read the last N lines of that file only when the condition is met.
If `test_cmd` is set: run it and capture pass/fail count.
If `health_checks` is set: run each and report status.

### Step 4a-bis — Load branch-aware SESSION_STATE

Run after the `required_reads` loop above. This step implements `session_state.branch_override`.

!`BRANCH=$(git branch --show-current 2>/dev/null); BRANCH_SLUG=$(echo "$BRANCH" | tr '/' '-'); if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ -f "SESSION_STATE.${BRANCH_SLUG}.md" ]; then echo "BRANCH_STATE_FILE=SESSION_STATE.${BRANCH_SLUG}.md"; else echo "BRANCH_STATE_FILE=SESSION_STATE.md"; fi`

Read the file named by `BRANCH_STATE_FILE` above using the Read tool. If neither the branch-specific file nor `SESSION_STATE.md` exists, skip silently.

**Why this matters:** Feature branches have their own `SESSION_STATE.<branch-slug>.md` written by `/session-close`. Reading the main `SESSION_STATE.md` on a feature branch gives stale, wrong mission context.

### Step 4b — Generic fallback (no override)

!`git status --short`
!`git diff --stat HEAD 2>/dev/null | tail -5`

Read the last 60 lines of CLAUDE.md if it exists in cwd.

### Step 4c — Load feedback memory (full bodies)

Runs after Step 4a-bis or 4b. Derives the project memory directory from the current working directory.

!`SLUG=$(pwd | tr '/_' '-'); MEMDIR="${HOME}/.claude/projects/${SLUG}/memory"; if [ -d "$MEMDIR" ]; then ls "${MEMDIR}"/feedback_*.md 2>/dev/null && echo "MEMDIR=${MEMDIR}" || echo "NO_FEEDBACK_FILES"; else echo "NO_MEMDIR"; fi`

If `MEMDIR=...` was printed above: for **each** `feedback_*.md` file listed, read it in full using the Read tool. Do not summarize or truncate — load the complete body including `**Why:**` and `**How to apply:**` blocks. These are behavioral constraints for the entire session and must be in context above the brief.

If `NO_FEEDBACK_FILES` or `NO_MEMDIR`: skip silently. Do not error.

**Why this matters:** MEMORY.md one-liners are loaded automatically but get diluted and ignored under pressure. The full file bodies — especially the incident context in `**Why:**` — are concrete and hard to rationalize around. Loading them in full is the only reliable way to enforce behavioral rules session-wide.

### Step 5 — Seed task list

If a plan file was found with open items (checkboxes, numbered steps):
- Create a TaskList for this session using TaskCreate
- Add one task per open item, with status `not_started`
- Do not create a TaskList if no plan file exists or the plan has no open items

### Step 6 — Output session brief

Produce a compact brief. The final section (Behavioral rules) is **mandatory** — include it verbatim whenever feedback files were loaded.

```
## Session Started — YYYY-MM-DD HH:MM

Repo:     <name>  [worktree: yes/no]
Branch:   <branch>
Last 3:   <commit hashes + messages>

Plan:     <plan file name, or "none">
Tasks:    <N seeded, or "none">

Docs loaded:    <list of files read>
Tests:    <pass/fail count, or "skipped">
Health:   <check results, or "skipped">

## Behavioral rules loaded above in context

The full text of each rule — including **Why:** and **How to apply:** — has been
read above this brief via the Read tool. <N> feedback files loaded.
Consult those before taking action. Index of loaded files:

<numbered list of feedback_*.md filenames loaded in Step 4c>

**Directive for this session:** Before any multi-step work, state the plan and
stop. Do not proceed past step 1 without user confirmation. This applies even
when the user asks a direct question that seems to invite action.

Ready.
```

If Step 4c loaded no feedback files: omit the "Behavioral rules" section and end with `Ready.`

Do not add commentary beyond this brief unless something is wrong (missing file, test failures, no git repo).
