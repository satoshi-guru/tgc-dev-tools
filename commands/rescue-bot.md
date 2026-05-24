---
description: Emergency bot rescue — close all positions, reset drawdown peak, restore risk params
allowed-tools: Bash
---

## Live bot state

Portfolio:
!`ssh root@82.223.152.26 "curl -s http://localhost:8000/api/portfolio/summary" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Equity \${d[\"total_equity\"]:.2f}  |  Util {d[\"total_utilization\"]:.1f}%  |  Positions {d[\"total_positions\"]}'); [print(f'  [{n}] equity=\${a[\"equity\"]:.2f}  util={a[\"utilization\"]:.0f}%  pos={a[\"positions\"]}') for n,a in d[\"accounts\"].items()]"`

Risk:
!`ssh root@82.223.152.26 "curl -s http://localhost:8000/api/risk" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'halted={d[\"halted\"]}  drawdown={d[\"drawdown_pct\"]:.1f}%  peak=\${d[\"peak_equity\"]:.2f}  heat={d[\"portfolio_heat_ratio\"]:.0f}x  hwm_drop={d.get(\"hwm_drop_pct\",0):.1f}%')"`

Open positions:
!`ssh root@82.223.152.26 "cd /home/bot/hl_claw_bot && source .venv/bin/activate && python3 -c \"import sys; sys.path.insert(0,'src'); from src.exchange.account_registry import registry; any_pos=False; [print(f'  [{n}] {c} {p.get(\"side\")} sz={float(p.get(\"size\",0)):.4f} upnl=\${float(p.get(\"unrealised_pnl\") or 0):.2f}') or setattr(__builtins__, \"_\", True) for n in registry.names for c,p in registry.get(n).get_open_positions().items()]\" 2>/dev/null || echo '  (none)'"`

## Your task

Run the full rescue sequence using the script at `scripts/rescue_bot.sh`. Execute it non-interactively by calling each step directly via SSH rather than the interactive script:

1. Close all open positions on all accounts via the exchange API
2. Trigger Grid MM emergency exit (cancel bids/asks, flatten ETH)  
3. Reset drawdown peak to current equity: `curl -s -X POST http://localhost:8000/api/risk/reset-peak`
4. Set drawdown threshold to 20%: `curl -s -X POST "http://localhost:8000/api/risk/set-max-drawdown?pct=20"`
5. Set heat ratio to 20×: `curl -s -X POST "http://localhost:8000/api/risk/set-heat-ratio?ratio=20"`
6. Report final state: halted status, new peak, drawdown %, heat ratio

Use `ssh root@82.223.152.26` for all remote commands. Bot dir is `/home/bot/hl_claw_bot`.
