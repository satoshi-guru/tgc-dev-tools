# Design Proposal: <what you're designing>

- **Date:** <YYYY-MM-DD>
- **Author:** design-review (DESIGN mode, principal-engineer pass)
- **Requirement:** <the problem in one or two sentences — what the user actually needs>
- **Area touched:** <modules / branch / service, from grounding>

## Constraints found in the code

> What the *existing code* forces on this design. Every line cited. This is the part
> that makes the proposal real instead of generic — if this section is thin, you
> haven't grounded enough.

- <e.g. "Item value is derived via `_gear_meta(template_id)` (discord_sidecar.py:4171),
  not stored — so any 'net worth' can't be a SQL `SUM` over a column.">
- <e.g. "Sidecar handlers all offload DB work via `asyncio.to_thread` (pattern at
  discord_sidecar.py:4195) — a new handler must follow it.">

## Options

### Option A — <name>
- **Shape:** <the architecture in 1–2 sentences>
- **Sketch:**
  ```python
  # real signatures / schema / wiring — matching the surrounding idioms
  ```
- **Buys:** <what's good about it>
- **Costs:** <what it sacrifices — be honest; every option has a cost>

### Option B — <name>
- **Shape / Sketch / Buys / Costs** as above.

### (Option C if a third shape is genuinely distinct.)

## Recommendation

**Option <X>** — <why it wins, in terms a reader could disagree with on purpose.
Reference the constraints above: it wins *because* of what the code forces.>

## Interface sketch (the recommended option, concrete)

```python
# The actual functions / schemas / endpoints you'd add, and the exact call that
# wires them in. Detailed enough that implementation is mechanical from here.
```

## Risks & second-order effects

- <What this forces elsewhere; coupling created; failure mode + how you'd notice it.>
- <The non-obvious one — the thing the requirement didn't mention but this design has
  to deal with.>

## Open questions

- <Genuine forks the user must decide — phrased so the answer changes the design.>

## Recommended next step

<Usually: hand to `superpowers:writing-plans` to turn this into an implementation
plan / prototype the one risky seam (<name it>) first / build it directly if small.>
