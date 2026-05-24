---
name: git-check
description: Pre-work git hygiene for the hl_claw_bot two-repo setup. Fetches both repos, reports branch state vs origin, flags dirty hot files, and lists open feature branches. Run at the start of every session or before pushing.
---

# Git Check — Pre-Work Hygiene

Run this before starting any implementation or before pushing. Covers both repos:
- **Main bot** (`hl_claw_bot`): `/home/rootvault/Dokumente/hl_claw_bot`
- **Game sandbox** (`hl_game_backend`): `/home/rootvault/Dokumente/hl_game_backend`

---

## Step 1 — Fetch Both Repos

```bash
git -C /home/rootvault/Dokumente/hl_claw_bot fetch origin --prune 2>&1 | sed 's/^/[claw] /'
git -C /home/rootvault/Dokumente/hl_game_backend fetch origin --prune 2>&1 | sed 's/^/[game] /'
```

---

## Step 2 — Branch Status

For each repo, report:
- Current branch
- Commits ahead / behind origin
- Whether origin exists for this branch

```bash
cd /home/rootvault/Dokumente/hl_claw_bot && \
  echo "[claw] branch: $(git branch --show-current)" && \
  git status -sb | head -1 && \
  git log --oneline origin/$(git branch --show-current)..HEAD 2>/dev/null | wc -l | xargs -I{} echo "[claw] {} commits ahead of origin" && \
  git log --oneline HEAD..origin/$(git branch --show-current) 2>/dev/null | wc -l | xargs -I{} echo "[claw] {} commits behind origin"

cd /home/rootvault/Dokumente/hl_game_backend && \
  echo "[game] branch: $(git branch --show-current)" && \
  git status -sb | head -1 && \
  git log --oneline origin/$(git branch --show-current)..HEAD 2>/dev/null | wc -l | xargs -I{} echo "[game] {} commits ahead of origin" && \
  git log --oneline HEAD..origin/$(git branch --show-current) 2>/dev/null | wc -l | xargs -I{} echo "[game] {} commits behind origin"
```

---

## Step 3 — Dirty Hot Files

Check for uncommitted changes in files that must not be touched without awareness:

```bash
cd /home/rootvault/Dokumente/hl_claw_bot && \
  git status --short | grep -E "(src/api/game_routes|src/api/routes|src/bot/loop|gamingstudio/discord_bot/bot|gamingstudio/discord_bot/cogs)" | \
  sed 's/^/[claw HOT] /' || echo "[claw] hot files clean"

cd /home/rootvault/Dokumente/hl_game_backend && \
  git status --short | grep -E "(src/api/game_routes|src/api/app|src/game/)" | \
  sed 's/^/[game HOT] /' || echo "[game] hot files clean"
```

---

## Step 4 — Open Feature Branches

List local branches not yet merged to main, with age:

```bash
cd /home/rootvault/Dokumente/hl_claw_bot && \
  echo "=== [claw] Open branches ===" && \
  git branch --no-merged main 2>/dev/null | grep -v "^\*" | while read b; do
    age=$(git log -1 --format="%ar" "$b" 2>/dev/null)
    behind=$(git log --oneline "$b"..main 2>/dev/null | wc -l | tr -d ' ')
    ahead=$(git log --oneline main.."$b" 2>/dev/null | wc -l | tr -d ' ')
    echo "  $b  [+$ahead/-$behind vs main | last: $age]"
  done

cd /home/rootvault/Dokumente/hl_game_backend && \
  echo "=== [game] Open branches ===" && \
  git branch | grep -v "^\*"
```

---

## Step 5 — Report

Output a summary in this format:

```
## Git Check — YYYY-MM-DD HH:MM

### hl_claw_bot
Branch: <name>  |  ahead: N  |  behind: N
Hot files dirty: <list or "none">

### hl_game_backend
Branch: <name>  |  ahead: N  |  behind: N
Hot files dirty: <list or "none">

### Open feature branches (hl_claw_bot)
<list with age and +ahead/-behind>

### Action needed
- [ ] Pull main if behind
- [ ] Stash or commit dirty hot files before branching
- [ ] Review open branches older than 14 days
```

Flag anything that requires action before proceeding.

---

## Guardrails

- Never switch branches without the user explicitly asking
- Never `git pull --force` or `git reset --hard` — just report divergence
- If both repos are clean and in sync: say so and exit
