# llmdoc Presets — Full Library Reference

All aliases usable with `/llmdoc <alias>`. Each maps to the canonical docs URL.

## Frontend / React Native (keyo)
| Alias | URL |
|-------|-----|
| expo | https://docs.expo.dev |
| expo-router | https://docs.expo.dev/router/introduction/ |
| expo-notifications | https://docs.expo.dev/versions/latest/sdk/notifications/ |
| react-native | https://reactnative.dev/docs/getting-started |
| react-navigation | https://reactnavigation.org/docs/getting-started |
| reanimated | https://docs.swmansion.com/react-native-reanimated/ |
| nativewind | https://www.nativewind.dev/docs |
| supabase | https://supabase.com/docs/reference/javascript/introduction |
| tailwind | https://tailwindcss.com/docs |
| typescript | https://www.typescriptlang.org/docs/ |
| zod | https://zod.dev |
| nextauth | https://authjs.dev/getting-started |
| trpc | https://trpc.io/docs |
| turbo | https://turbo.build/repo/docs |
| pnpm | https://pnpm.io/pnpm-workspace_yaml |
| vitest | https://vitest.dev/guide |
| prisma | https://www.prisma.io/docs |

## Python Backend (hl_claw_bot / hl_game_backend)
| Alias | URL |
|-------|-----|
| python | https://docs.python.org/3/ |
| asyncio | https://docs.python.org/3/library/asyncio.html |
| fastapi | https://fastapi.tiangolo.com/reference/ |
| pydantic | https://pydantic.dev/docs/validation/latest/get-started/ |
| aiohttp | https://docs.aiohttp.org/en/stable/ |
| httpx | https://www.python-httpx.org/ |
| uvicorn | https://www.uvicorn.org/ |
| websockets | https://websockets.readthedocs.io/en/stable/ |
| pytest | https://docs.pytest.org/en/stable/ |
| ruff | https://docs.astral.sh/ruff/ |
| scikit-learn | https://scikit-learn.org/stable/ |
| sentence-transformers | https://sbert.net/ |
| pygithub | https://pygithub.readthedocs.io/en/stable/ |

## Discord
| Alias | URL |
|-------|-----|
| discordpy | https://discordpy.readthedocs.io/en/stable/ |
| discord-api | https://discord.com/developers/docs/intro |

## AI / LLM / Agents
| Alias | URL |
|-------|-----|
| anthropic | https://docs.anthropic.com/en/api/ |
| openai-agents | https://openai.github.io/openai-agents-python/ |
| openai | https://platform.openai.com/docs/overview |
| mcp | https://modelcontextprotocol.io/docs/ |

## Crypto / Trading
| Alias | URL |
|-------|-----|
| hyperliquid | https://hyperliquid.gitbook.io/hyperliquid-docs/ |
| ethers | https://docs.ethers.org/v6/ |
| viem | https://viem.sh/docs/getting-started |

## Infrastructure / Data
| Alias | URL |
|-------|-----|
| sqlite | https://www.sqlite.org/docs.html |
| notion | https://developers.notion.com/reference/intro |
| git | https://git-scm.com/docs |
| systemd | https://www.freedesktop.org/software/systemd/man/latest/ |
| bash | https://www.gnu.org/software/bash/manual/bash.html |
| nginx | https://nginx.org/en/docs/ |

---

# Project Preset Groups

One-liner refresh per project. Invoke with `/llmdoc preset:<group>` — fetches every lib in the group sequentially.

**Fusion syntax** for cross-workspace tasks: combine with `+` (e.g. `/llmdoc preset:notion-workspace+x-promo+discord-bot` for a coordinated Notion/X/Discord push). Duplicates are deduped before fetching.

| Group | Libraries | Use when |
|-------|-----------|----------|
| `keyo` | expo, expo-router, expo-notifications, react-native, react-navigation, reanimated, supabase, typescript | Working in `/home/rootvault/Dokumente/keyo/keyo-app/` |
| `hl_bot` | hyperliquid, fastapi, pydantic, aiohttp, httpx, websockets, pytest, ruff, sqlite, systemd, nginx | Working in `/home/rootvault/Dokumente/hl_claw_bot/` |
| `hl_game` | hyperliquid, fastapi, pydantic, aiohttp, websockets, openai-agents, openai, sqlite, systemd, ethers, viem | Working in `/home/rootvault/Dokumente/hl_game_backend/` (core game backend, no Discord) |
| `discord-bot` | discordpy, discord-api, fastapi, pydantic, sqlite | Working in `gamingstudio/discord_bot/` or any standalone Discord bot |
| `notion-workspace` | notion, mcp, anthropic, openai | Notion content authoring, MCP integrations, Notion-driven knowledge work |
| `x-promo` | openai, anthropic, httpx | X/Twitter promotion, marketing copy generation, social posting scripts |
| `gaming-studio` | discord-api, discordpy, hyperliquid, fastapi, pydantic, sqlite, openai-agents | `gamingstudio/` sub-project (Discord-driven game ops, distinct from `hl_game` core) |
| `happy-tool` | typescript, drizzle-orm, fastify, vitest, prisma, pnpm, turbo | HappyTool stack (TS + Drizzle + Vitest + real test DB) |

**Common fusion combos:**

| Combo | When |
|-------|------|
| `preset:notion-workspace+x-promo` | Drafting X posts from Notion content |
| `preset:notion-workspace+discord-bot` | Pushing Notion updates to a Discord channel |
| `preset:notion-workspace+x-promo+discord-bot` | Coordinated multi-channel announcement |
| `preset:hl_game+discord-bot` | Wiring the game backend to a Discord notifier |
| `preset:hl_bot+hl_game` | Sharing utilities between trading bot and game backend |

**Editing this table:** keep groups minimal — each group should reflect what you *actually code against* in that project, not aspirational tooling. If a lib is used in one file once a year, leave it out and `/llmdoc <alias>` it ad-hoc.
