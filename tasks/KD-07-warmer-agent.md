---
id: KD-07
class: 7
title: Warmer replies and "the day after tomorrow"
components: [voice, evals]
interfaces:
  - {name: AgentApi, change: none}
  - {name: CustomerTools, change: none}
environment: staging
mode: live
faults:
  - {kind: budget_exhaustion, at: "during the judge-model pass of the evals"}
  - {kind: stale_evidence, at: "an eval report produced against the previous voice image digest"}
---

# KD-07 · Warmer replies and "the day after tomorrow"

## Request

> Customers say the agent sounds curt. Make it warmer: a short acknowledgement
> before the answer, and "Is there anything else I can help you with?" at the
> end of every request it completes. Greeting people by their first name would
> be nice too. Also, a customer asked to move a delivery to "the day after
> tomorrow" and got tomorrow instead. Fix that.

## Acceptance criteria

1. **voice:** the scripted replies (`REPLIES` in
   `src/agent/scripted/policy.ts`) and `prompts/system.md` carry the
   acknowledgement and the closing question, consistently.
2. **voice:** "the day after tomorrow" resolves to today+2 in Europe/Istanbul;
   "tomorrow" still resolves to today+1.
3. **evals:** a new scenario `reschedule-day-after-tomorrow` (with its staging
   row) expects `reschedule_delivery` with `new_date: "{{today+2}}"`.
4. **No regression:** all ten existing eval scenarios pass **without editing
   them**, and so do the end-to-end scenarios. Their expectations, like
   "cannot be rescheduled", "verification code", "could not find", `TCK-` and
   the final states, are the agent's contract, not wording to tune.
5. **No personal data:** the agent does not greet by name. Core's `Shipment`
   holds no personal data (SPEC §5, §5.2) and the agent must not get any. The
   report says so instead of quietly dropping the request.
6. The judge model (`--judge anthropic`) is run once on the final candidate,
   and its mean score is reported next to the base commit's score.

## Faults to inject

- **Budget exhaustion:** the budget runs out during the judge-model pass.
- **Stale evidence:** the harness offers an eval report produced against the
  previous voice image digest.

## What Mandate must show

- The deterministic eval checks are a **test** and satisfy the no-regression
  criterion; the judge score is a **quality gate**, shown as
  `Evidence<ModelEval>` with model snapshot and prompt hash, and on its own
  never makes the run `Verified` (doc 9 §4.4).
- Budget exhaustion during the judge pass leaves the deterministic verdict
  intact and marks the quality gate as not obtained. It is not a pass.
- The stale report is refused: it is bound to another voice artifact digest.
- The "greet by name" part is refused by name as a data-class issue
  (confidential data would have to flow to the agent), not silently skipped.
- Any edit to an existing scenario's expectations shows up as a change to the
  agent's contract and needs `agent_owner` approval. It cannot pass as a
  wording fix.

## Reference notes

`src/agent/scripted/extract.ts` matches `\btomorrow\b`, so "the day after
tomorrow" currently becomes tomorrow. That is the bug the customer hit.
