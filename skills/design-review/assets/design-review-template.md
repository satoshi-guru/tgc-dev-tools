# Design Review: <design name>

- **Date:** <YYYY-MM-DD>
- **Reviewer:** design-review (staff-engineer pass)
- **Design source:** <plan file / conversation / draft module — where the design came from>
- **Area touched:** <modules / branch / service this affects>

## Verdict

**<Approve | Approve with changes | Needs rework>** — <one-line rationale a busy
engineer can act on without reading the rest>.

## What's being designed

<2–4 sentences restating the design in your own words: what changes, what's new,
what problem it solves. This is the version you confirmed with the author.>

## Constraints found in the code

> What the existing code actually says about this area — cited. Read before judged.
> Every "X already exists" / "Y is a hot file" / "Z breaks an invariant" below traces
> to a `file:line` here.

- <e.g. "`funding` signal already exists: `CONFLUENCE_WEIGHTS['funding']=0.10`
  (confluence.py:17), logic at confluence.py:223–229, fed from tools.py:776.">

## Strengths

- <What's genuinely right about this design — name it, don't pad. If it's solid, say
  so; a review that only lists problems isn't honest.>

## Concerns (severity-ordered)

> Lead with what breaks production / money / data. Nitpicks go last, clearly marked.

### 🔴 Blocking — <short title>
- **Issue:** <what's wrong>
- **Why it matters:** <the concrete consequence — the incident this causes>
- **Recommendation:** <the specific change that fixes it>

### 🟡 Should-fix — <short title>
- **Issue / Why / Recommendation** as above.

### 🟢 Consider — <short title>
- <Optional improvements, naming, style. Safe to defer.>

## Invariant & convention check

| Check | Status | Note |
|---|---|---|
| Lands in correct module / branch | ✅/⚠️/❌ | |
| Doesn't duplicate existing code | ✅/⚠️/❌ | |
| Hot files: new module + minimal wiring | ✅/⚠️/❌ | |
| No blocking I/O on async event loop | ✅/⚠️/❌ | |
| Shared state thread-safe / singletons reused | ✅/⚠️/❌ | |
| Named invariants preserved | ✅/⚠️/❌ | <which ones apply> |
| Fails loud, no silent fallback | ✅/⚠️/❌ | |
| Typed contracts / boundary validation | ✅/⚠️/❌ | |
| Conventions (dead-code, secrets, --from-vps) | ✅/⚠️/❌ | |

(Drop rows that don't apply; add area-specific invariants that do.)

## Alternatives considered

- **Option A (chosen):** <shape> — <why it wins>
- **Option B:** <shape> — <why rejected>

## Open questions

- <Anything still unresolved that the author needs to decide before building.>

## Recommended next step

<One of: hand to `superpowers:writing-plans` to produce the implementation plan /
prototype the risky seam (<name it>) before committing / go build it as-is /
rework the design and re-review.>
