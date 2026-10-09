---
id: KD-10
class: 2
title: Replace estimatedDelivery with a delivery object in core's API
components: [core, voice]
interfaces:
  - {name: CoreApi, change: breaking}
  - {name: CustomerTools, change: none}
environment: staging
mode: live
faults:
  - {kind: unknown_outcome_at_merge, at: "merge of the kervan-core member of the contract step"}
  - {kind: flaky_ci, at: "kervan-voice CI in the migrate step"}
---

# KD-10 · Replace `estimatedDelivery` with a `delivery` object in core's API

## Request

> The shipment answer only tells the agent the delivery date. Customers also
> ask which window the courier comes in and whether the delivery was already
> moved. In core's `Shipment`, replace `estimatedDelivery` with
> `delivery: {date, window, status}` (null when there is no delivery row), and
> make the agent mention the window. Nothing may break for customers while
> this rolls out.

## Acceptance criteria

1. Final state: core's `Shipment` has `delivery` and no `estimatedDelivery`;
   `docs/openapi.json` says so; the agent's status reply contains the date and
   the window ("… Estimated delivery: 2026-10-13 (morning).").
2. Delivered as **expand → migrate → contract**:
   - **expand** (core): `delivery` added next to `estimatedDelivery`;
   - **migrate** (voice): the agent reads `delivery`, and falls back to
     `estimatedDelivery` while the field still exists;
   - **contract** (core): `estimatedDelivery` removed.
3. After every step `scripts/e2e.sh` exits 0, including `e2e-status-lookup`,
   which checks "Estimated delivery: {{today+3}}", and every eval scenario
   passes.
4. kervan-mcp needs no change: it passes core's answer through as the tool
   result.

## Faults to inject

- **Unknown outcome at merge:** the contract step's core merge returns no
  answer; the PR was merged.
- **Flaky CI:** kervan-voice's CI fails once in the migrate step.

## What Mandate must show

- The plan declares `CoreApi` `breaking` and the three steps; the compiler
  refuses a single step.
- **The hidden consumer:** the system model says `mcp` consumes `CoreApi` and
  `voice` consumes `CustomerTools`. But mcp passes core's JSON through, and
  `docs/mcp-tools.json` declares no output schema, so the `CustomerTools`
  contract diff is empty in every step. The real consumer of the removed field
  is voice, two hops away. A plan that changes only core is caught by
  `test.integration` (`e2e-status-lookup` fails), not by any contract diff.
  The run must surface this as a finding about the model, either "CustomerTools
  results carry CoreApi shapes" or a request to declare tool output schemas.
- The reconciled contract merge is recorded once.
