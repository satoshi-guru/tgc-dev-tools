---
name: llmdoc
description: Fetch docs for any library and save them locally as LLM-ready markdown under docs/<slug>/. Use BEFORE writing config or code for an unfamiliar or recently-changed library API. Use immediately when a first install/build/run attempt fails — don't retry with workarounds first.
argument-hint: "[alias | <url>] — see presets table below"
allowed-tools: Bash Read WebFetch WebSearch
---

Fetch documentation and save to `docs/<slug>/` in the current project.

Arguments: $ARGUMENTS

## Common presets

### Frontend / React Native (keyo)
| Alias | Fetches |
|-------|---------|
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
| pnpm | https://pnpm.io/pnpm-workspace_yaml + https://pnpm.io/settings |
| vitest | https://vitest.dev/guide |
| prisma | https://www.prisma.io/docs |

### Python backend (hl_claw_bot / hl_game_backend)
| Alias | Fetches |
|-------|---------|
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

### Discord
| Alias | Fetches |
|-------|---------|
| discordpy | https://discordpy.readthedocs.io/en/stable/ |
| discord-api | https://discord.com/developers/docs/intro |

### AI / LLM / Agents
| Alias | Fetches |
|-------|---------|
| anthropic | https://docs.anthropic.com/en/api/ |
| openai-agents | https://openai.github.io/openai-agents-python/ |
| openai | https://platform.openai.com/docs/overview |
| mcp | https://modelcontextprotocol.io/docs/ |

### Crypto / Trading
| Alias | Fetches |
|-------|---------|
| hyperliquid | https://hyperliquid.gitbook.io/hyperliquid-docs/ |
| ethers | https://docs.ethers.org/v6/ |
| viem | https://viem.sh/docs/getting-started |

### Infrastructure / Data
| Alias | Fetches |
|-------|---------|
| sqlite | https://www.sqlite.org/docs.html |
| notion | https://developers.notion.com/reference/intro |
| git | https://git-scm.com/docs |
| systemd | https://www.freedesktop.org/software/systemd/man/latest/ |
| bash | https://www.gnu.org/software/bash/manual/bash.html |
| nginx | https://nginx.org/en/docs/ |

For any alias not listed above, treat it as a raw URL.

## Project preset groups

For one-command per-project refresh, use `preset:<group>`. Groups live in `PRESETS.md` under **Project Preset Groups** — they expand to a list of aliases.

Combine groups with `+` for cross-workspace tasks: `/llmdoc preset:notion-workspace+x-promo+discord-bot`. Libs are deduped before fetching.

Examples:
- `/llmdoc preset:keyo` — full keyo doc refresh (expo stack + supabase)
- `/llmdoc preset:hl_game` — full game backend doc refresh
- `/llmdoc preset:notion-workspace+discord-bot` — fusion for Notion→Discord work
- `/llmdoc expo supabase` — ad-hoc, no preset group

## Task

1. **Parse $ARGUMENTS** — each token is one of:
   - `preset:<group>` or `preset:<group1>+<group2>+...` → expand to the group's alias list (see PRESETS.md "Project Preset Groups"). Dedupe across multiple groups.
   - A known alias from the preset table → map to the URL.
   - Anything else → treat as a raw URL.
2. For known aliases, map to the URL(s) in the alias tables. For unknown tokens, use as raw URL.
3. Run the fetcher for each target:

```bash
/home/rootvault/Dokumente/llmdocs/.venv/bin/python \
  /home/rootvault/Dokumente/llmdocs/llmdocs.py \
  --url <URL> \
  --workers 4 --rate-limit 0.25 \
  --out docs/<slug>/
```

The fetcher defaults: `--max-pages 5000`, `--workers 1`, `--rate-limit 0.5`, auto-deletes `_raw_html/` cache after success. For **batch refresh (preset groups, multiple libs)** always pass `--workers 4 --rate-limit 0.25` — gives ~3.5x speedup with same effective per-host rate (1 req/sec across workers). For single ad-hoc fetches, defaults are fine.

Skip patterns built-in: non-English locales (`/fr/`, `/zh_HANS-CN/`), version-pinned paths (`/2.43.0/`), and version aliases (`/latest/`, `/main/`, `/master/`, `/dev/`). Pass `--keep-html` only when debugging.

Where `<slug>` is the alias name or a kebab-case version of the URL's hostname/path.
Output goes to `docs/<slug>/` relative to the current working directory.

4. Run targets sequentially (each fetch is network-bound).
5. After each fetch: report target, pages written, output path, any errors.
6. **After ALL fetches succeed, auto-chain `/doc-indexer`** for every freshly-fetched lib. This builds the `COMPACT.md` token-cheap layer (~800 tokens vs ~40k raw) that downstream sessions read by default. Never skip this step — the indexed layer is the point of the workflow.
7. Final summary table: alias → pages → path → COMPACT.md status.
8. Tell the user: "Docs available at @docs/<slug>/ — use COMPACT.md for cheap lookups, raw .md files for deep dives."
