---
name: analyze-trade
description: Deep-dive analysis of a single closed trade. Queries memory.db and DCL candles to explain entry, exit, TP/SL outcome, and price action context.
argument-hint: "<oid>  |  <COIN HH:MM>  |  <COIN HH:MM:SS>"
disable-model-invocation: true
allowed-tools: Bash Read
---

Analyze a single closed trade in full detail.

## Step 1 — Resolve the trade

Parse `$ARGUMENTS`:

**If numeric (OID):** query by entry_oid
```!
ssh root@82.223.152.26 "cd /home/bot/hl_claw_bot && source .venv/bin/activate && python3 - <<'EOF'
import sys; sys.path.insert(0,'src')
from src.memory.engine import engine
import json
rows = engine.conn.execute("""
    SELECT t.*, p.pnl_usdt, p.close_price as pnl_close, p.reason as close_reason
    FROM trades t LEFT JOIN pnl_log p ON t.id = p.trade_id
    WHERE t.entry_oid = ? OR t.id = ?
    ORDER BY t.created_at DESC LIMIT 1
""", ('$ARGUMENTS', '$ARGUMENTS')).fetchall()
if rows:
    cols = [d[0] for d in engine.conn.execute('SELECT * FROM trades LIMIT 0').description or []]
    print(json.dumps(dict(zip(cols, rows[0])), default=str, indent=2))
else:
    print('NOT FOUND')
EOF"
```

**If coin + time (e.g. "ZRO 22:46" or "ZRO 22:46:10"):** query by coin and approximate timestamp
```!
ssh root@82.223.152.26 "cd /home/bot/hl_claw_bot && source .venv/bin/activate && python3 - <<'EOF'
import sys; sys.path.insert(0,'src')
from src.memory.engine import engine
import json

args = '$ARGUMENTS'.split()
coin = args[0].upper()
time_str = args[1] if len(args) > 1 else ''

rows = engine.conn.execute("""
    SELECT t.*, p.pnl_usdt, p.close_price as pnl_close, p.reason as close_reason
    FROM trades t LEFT JOIN pnl_log p ON t.id = p.trade_id
    WHERE t.coin = ?
      AND time(datetime(t.created_at/1000, 'unixepoch', 'localtime')) LIKE ?
    ORDER BY t.created_at DESC LIMIT 3
""", (coin, time_str[:5] + '%')).fetchall()

cols = [d[0] for d in engine.conn.execute('PRAGMA table_info(trades)').fetchall()]
col_names = [r[1] for r in cols]
for r in rows:
    print(json.dumps(dict(zip(col_names, r)), default=str, indent=2))
    print('---')
EOF"
```

If not found on VPS, try local: `PYTHONPATH=src .venv/bin/python3` with same queries against `data/memory.db`.

---

## Step 2 — Fetch price action context

Use the trade's `coin` and `created_at` timestamp. Fetch 1m candles: 10 minutes before entry through 15 minutes after.

```!
ssh root@82.223.152.26 "curl -s 'http://localhost:8000/api/dcl/candles?coin=ZRO&interval=1m&limit=30' 2>/dev/null | python3 -c \"import json,sys; data=json.load(sys.stdin); [print(f'{c[\\\"t\\\"]}  o={c[\\\"o\\\"]:.4f}  h={c[\\\"h\\\"]:.4f}  l={c[\\\"l\\\"]:.4f}  c={c[\\\"c\\\"]:.4f}') for c in data[-30:]]\" 2>/dev/null"
```

Replace `ZRO` with the actual coin from Step 1. This gives you the raw OHLCV context.

---

## Step 3 — Analyse and report

Using the trade record + candle data, answer:

1. **Did price reach TP?**
   Compare TP price against candle highs (LONG) or lows (SHORT) during the trade window.
   If yes but `tp_missed` → order execution issue (post-only rejection, latency, partial fill).
   If no → price reversed before reaching TP.

2. **Entry quality**
   Was entry price at a reasonable level vs the preceding candles? Was it near range_low (for LONG scalp)?

3. **Exit analysis**
   What was the actual close price and reason? Cross-check `close_reason` from `pnl_log`.
   `tp_missed` + positive PnL usually means: SL trailed to breakeven and price moved favourably but TP order failed.

4. **Duration vs strategy**
   5.5m for a `scalp_6m` is expected. Was this within normal range?

5. **Verdict**
   One sentence: what happened and whether it was a system issue, market behaviour, or normal outcome.

---

## Output format

```
## Trade Analysis — <COIN> <SIDE> @ <entry_price>  (<date> <time>)

Strategy:   <strategy_type>  |  Account: <account>
Entry:      $<entry_price>  →  Close: $<close_price>  (TP target: $<tp_price>)
Result:     <result>  |  PnL: <pnl_usdt>  |  Duration: <duration>

### Price action (<coin> 1m candles)
<table of candles around entry window, highlight: entry candle, TP level, close candle>

### What happened
<2-4 sentences: did price reach TP, why was the result what it was>

### Entry quality
<1-2 sentences>

### Verdict
<one sentence>
```
