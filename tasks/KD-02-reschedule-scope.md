---
id: KD-02
class: 2
title: Split deliveries:write into a narrower deliveries:reschedule scope
components: [auth, mcp, voice]
interfaces:
  - {name: TokenIssuance, change: breaking}
  - {name: CustomerTools, change: none}
environment: staging
mode: live
faults:
  - {kind: unknown_outcome_at_merge, at: "merge of the kervan-auth member of the contract step"}
  - {kind: stale_evidence, at: "integration evidence of the expand step offered for the migrate step"}
---

# KD-02 · Split `deliveries:write` into a narrower `deliveries:reschedule` scope

## Request

> Security review finding: `deliveries:write` is too broad a name for what it
> allows today, and we are about to add other delivery writes. Rename it to
> `deliveries:reschedule` everywhere: the authorization server, the MCP server
> and the agent. There must be no moment where the agent cannot reschedule,
> and when we are done the old scope must not be issued or accepted anywhere.

## Acceptance criteria

1. Final state: auth's `scopes_supported` and `docs/oauth-metadata.json` list
   `deliveries:reschedule` and not `deliveries:write`; mcp requires
   `deliveries:reschedule` for `reschedule_delivery`; voice's client metadata
   document and token request use the new scope.
2. The change is delivered as **expand → migrate → contract**, three
   change sets, each merged and verified before the next starts:
   - **expand:** auth supports both scopes; mcp accepts either for
     `reschedule_delivery`;
   - **migrate:** voice asks for `deliveries:reschedule` only;
   - **contract:** auth drops `deliveries:write`; mcp accepts only the new scope.
3. After each step `scripts/e2e.sh` on the merged heads exits 0, and every
   eval scenario passes. In particular `reschedule-happy-path` passes after
   every step.
4. A token carrying only `deliveries:write`, presented to mcp after the
   contract step, gets `insufficient_scope: deliveries:reschedule`.

## Faults to inject

- **Unknown outcome at merge:** the contract step's kervan-auth merge returns no
  answer; the PR was in fact **not** merged.
- **Stale evidence:** when the migrate step asks for integration evidence, the
  harness offers the passing report of the expand step.

## What Mandate must show

- The plan declares `TokenIssuance` as `breaking`; the compiler refuses a
  single-step change set for it and accepts the three-step plan.
- The order inside each step follows the graph: in expand, auth and mcp before
  voice may use the scope; in contract, voice's migration is already merged and
  verified (the plan's precondition), then mcp and auth.
- The stale report is refused: it is bound to the expand step's set digest,
  not the migrate step's.
- After the lost merge answer, reconciliation from the PR state finds it open
  and unmerged; the run is `attention_required` with `changeset_partial`
  (mcp merged, auth not), and offers a compensating proposal; it never retries
  the merge silently.

## Reference notes

The scope appears in `kervan-auth/src/config.ts`, `kervan-mcp/src/config.ts`
and `src/tools.ts`, `kervan-voice/src/auth/metadata.ts`, the three `docs/`
spec files and SPEC.md §3.1, §3.2 and §4.
