---
name: gemini-review
description: Quality gate for Gemini-authored code before porting to main. Checks against 9 known Gemini failure patterns specific to this project. Produces a P1/P2/P3 findings report. Run before any port-feature or manual extraction from game-backend.
---

# Gemini Code Review

Run this on any Gemini-authored code before porting it to main. Gemini writes structurally valid Python but has recurring patterns that cause silent runtime failures. Catch them here, not in production.

**Rule**: We never copy-paste Gemini's code — we review, upgrade, and straighten it.

---

## Invoke This Skill When

- User says "review Gemini's work", "check before porting", "gemini-review <feature>"
- Before running `/port-feature`
- Any time you're reading a game-backend feature authored by Gemini

---

## Step 1 — Identify the Code

Read the specified files from `hl_game_backend`:
- `/home/rootvault/Dokumente/hl_game_backend/src/api/game_routes.py` — game API routes
- `/home/rootvault/Dokumente/hl_game_backend/src/game/<module>.py` — game logic modules
- `/home/rootvault/Dokumente/hl_game_backend/gamingstudio/discord_bot/` — Discord bot

If no specific files given, ask: "Which feature or module in game-backend should I review?"

---

## Step 2 — Run the 9-Pattern Check

Check each pattern in order. For each finding, record: severity, file, line range, description, fix.

### P1 — Silent HTTP Error Eating
**Pattern**: `await r.json()` called without checking `r.status` first.
```python
# BAD — eats 404/500 as if they were valid JSON
async with session.get(url) as r:
    return await r.json()

# GOOD
async with session.get(url) as r:
    if r.status >= 400:
        logger.warning(f"API error {r.status} for {url}")
        return None
    return await r.json()
```
**Impact**: Every broken endpoint returns `None` silently — failure invisible until downstream crash.

### P1 — Nonexistent Backend Routes
**Pattern**: Calling an API path that doesn't exist in `src/api/game_routes.py` or `src/api/game_isekai_routes.py`.
```python
# BAD — these routes have never existed on the Python backend:
await bot.api("/gear/recipes")          # no recipes endpoint
await bot.api("/territory/map")         # no territory/map endpoint
await bot.api("/season/prestige_status") # wrong path prefix
```
**Check**: For every `bot.api("/<path>")` call in Discord cogs, grep for the path in game_routes.py:
```bash
grep -n "\"/<path>" /home/rootvault/Dokumente/hl_claw_bot/src/api/game_routes.py
```

### P1 — Wrong discord.py Method Signatures
**Pattern**: Calling discord.py methods with keyword arguments that don't exist.
```python
# BAD
await bot.fetch_entitlements(guild=interaction.guild)  # guild= is not a valid kwarg

# GOOD — check discord.py docs for exact signature
await bot.fetch_entitlements(user_id=interaction.user.id, exclude_ended=True)
```

### P1 — Missing Access Control
**Pattern**: Showing privileged UI (faction join, isekai tabs) without calling `require_access()` first.
```python
# BAD — no gate
async def join(self, interaction):
    await interaction.response.send_message(view=FactionSelectView())

# GOOD
async def join(self, interaction):
    if not await require_access(interaction.client, interaction):
        return
    await interaction.response.send_message(view=FactionSelectView())
```

### P1 — Fake Success Without API Call
**Pattern**: Modal or button that shows a "success" message without calling any endpoint.
```python
# BAD — looks like it works, does nothing
async def on_submit(self, interaction):
    await interaction.response.send_message("✅ Bounty Posted!", ephemeral=True)
    # No API call ever made
```
**Fix**: Either wire the real endpoint or replace with "Coming Soon" honestly.

### P2 — Wrong Response Field Names
**Pattern**: Accessing response fields by names that don't match what the backend returns.
```python
# BAD — backend returns {"season_id": ..., "leaderboard": [...]}
data["season"]    # KeyError
data["entries"]   # KeyError

# GOOD — match backend response schema exactly
data["season_id"]
data["leaderboard"]
```
**Check**: Read the actual route in game_routes.py and match field names.

### P2 — asyncio.sleep() Inside Event Handlers
**Pattern**: `asyncio.sleep()` directly inside `on_member_join` or similar event handlers. Holds the handler open for burst joins.
```python
# BAD
async def on_member_join(self, member):
    await asyncio.sleep(30)        # blocks the handler
    await member.send("Welcome!")

# GOOD
async def on_member_join(self, member):
    asyncio.create_task(self._send_welcome(member))

async def _send_welcome(self, member):
    await asyncio.sleep(30)
    await member.send("Welcome!")
```

### P2 — Hardcoded Data That Should Come From Backend
**Pattern**: Gemini hardcodes lists/dicts (gear recipes, rank ladders, item pools) that already exist in the Python backend.
```python
# BAD — duplicated, will drift
GEAR_RECIPES = [{"key": "iron_sword", "name": "Iron Sword", ...}]

# ACCEPTABLE ONLY IF backend has no list endpoint (document why)
# Reference the backend dict: GEAR_RECIPES in game_routes.py line ~N
```

### P3 — Bare Except / No Logging
**Pattern**: `except:` or `except Exception:` without logging the error.
```python
# BAD
try:
    result = await bot.api("/some/path")
except:
    pass

# GOOD
try:
    result = await bot.api("/some/path")
except Exception as e:
    logger.warning(f"Failed to fetch /some/path: {e}")
    result = None
```

---

## Step 3 — Output Report

```
## Gemini Review — <feature name> — YYYY-MM-DD

Files reviewed: <list>

### P1 — Must Fix Before Porting (N findings)
| # | Pattern | File | Lines | Fix |
|---|---------|------|-------|-----|
| 1 | Silent HTTP error eating | cogs/forge.py | 45-52 | Add status check before r.json() |
...

### P2 — Upgrade While Porting (N findings)
| # | Pattern | File | Lines | Fix |
|---|---------|------|-------|-----|
...

### P3 — Polish (N findings)
| # | Pattern | File | Lines | Fix |
|---|---------|------|-------|-----|
...

### Verdict
- P1 blockers: N  → [BLOCK / CLEAR]
- Code quality: [POOR / ACCEPTABLE / GOOD]
- Recommendation: <port with upgrades / rewrite / block>
```

P1 count > 0 → code needs fixes before or during porting. Never port P1 bugs as-is.

---

## Guardrails

- Do NOT fix the code in game-backend — only report findings
- game-backend is Gemini's sandbox — never commit fixes there
- Fixes go into the ported version in main
