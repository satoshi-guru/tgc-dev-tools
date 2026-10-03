# PRESETS — project preset groups for /llmdoc

`/llmdoc preset:<group>` expands a group to its alias list; each alias is then resolved
against the `llmdoc` skill's alias tables (the single source of truth). Combine groups
with `+` (`/llmdoc preset:keyo+discord-bot`); aliases are deduped before fetching.

**Every alias used below must exist in `SKILL.md`'s alias tables — add new aliases there,
not here.**

## Project Preset Groups

| Group | Aliases |
|-------|---------|
| `keyo` | expo, expo-router, expo-notifications, expo-device, supabase, react-native |
| `hl_game` | python, asyncio, fastapi, pydantic, httpx, websockets, pytest, hyperliquid |
| `hl_claw` | python, asyncio, httpx, websockets, pytest, hyperliquid |
| `discord-bot` | discordpy, discord-api |
| `notion-workspace` | notion |

## Not yet defined (referenced in examples — add when needed)

- `x-promo` — X/Twitter promotion stack. No X/Twitter alias exists in `SKILL.md` yet;
  add one (and the group) before using `preset:x-promo`.

## Adding a group

1. Ensure each alias exists in `SKILL.md`'s alias tables (add the row if missing).
2. Add a row here mapping `<group>` → comma-separated alias list.
Groups are derived from the per-project presets in `~/.claude/CLAUDE.md`; keep them in sync.
