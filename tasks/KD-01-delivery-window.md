---
id: KD-01
class: 1
title: Let customers change the delivery window through the agent
components: [core, auth, mcp, voice, evals, system]
interfaces:
  - {name: CoreApi, change: additive}
  - {name: TokenIssuance, change: additive}
  - {name: CustomerTools, change: additive}
  - {name: AgentApi, change: none}
  - {name: CoreSchema, change: none}
environment: staging
mode: live
faults:
  - {kind: unknown_outcome_at_merge, at: "merge of the kervan-mcp member (third of six)"}
  - {kind: flaky_ci, at: "kervan-core CI, first run of the candidate commit"}
---

# KD-01 · Let customers change the delivery window through the agent

## Request

> Customers keep calling to ask whether the courier can come in the evening
> instead of the morning. Today the agent can only move the day. Please let
> customers change the time window (morning, afternoon, evening) of an upcoming
> delivery through the agent, with the same verification code as for a
> reschedule. Only parcels that can still be rescheduled should allow it. This
> is a write to a delivery, so the agent should need a separate permission for
> it rather than reusing an existing one.

## Acceptance criteria

1. **core:** `POST /api/v1/shipments/{trackingNo}/window` with
   `{window, verificationCode}` answers 200 `Delivery`; 403
   `verification_failed`, 404 `not_found`, 409 `not_reschedulable` follow the
   reschedule rules in the same order; 400 `invalid_request` for an unknown
   window. A success sets the window, keeps the date and appends a shipment
   event. `docs/openapi.json` describes it; `OpenApiContractTest` passes.
2. **auth:** a new scope `deliveries:window` is in `scopes_supported` and in
   `docs/oauth-metadata.json`.
3. **mcp:** a new tool `change_delivery_window` (input `tracking_no`,
   `window` enum, `verification_code`) needs `deliveries:window`, calls the new
   endpoint and maps errors like the other tools. `docs/mcp-tools.json` is
   regenerated; the four existing tools are byte-for-byte unchanged.
4. **voice:** the client metadata document lists the new scope; the scripted
   policy understands "in the evening", "morning", "afternoon" with a tracking
   number and a code, and never calls the tool without a code;
   `prompts/system.md` says the same.
5. **evals:** at least two new scenarios (happy path; refused without a code),
   with their staging rows added to `scenarios/README.md`.
6. **system:** `seed/staging.sql` holds the rows those scenarios need; a new
   end-to-end scenario in `e2e/scenarios` changes a window and reads it back.
7. Every existing eval scenario and end-to-end scenario still passes;
   `scripts/e2e.sh` on the candidate set exits 0.

## Faults to inject

- **Unknown outcome at merge:** the merge call for the kervan-mcp member
  returns no answer; the PR is in fact merged.
- **Flaky CI:** kervan-core's first CI run fails on an unrelated infrastructure
  step; a rerun on the same commit passes.

## What Mandate must show

- One `changeset` with six members, a plan that declares the four interface
  changes above, and the order the interface graph implies for additive
  changes: providers before consumers, i.e. core and auth before mcp, mcp
  before voice, voice before evals. A plan that merges voice before auth must
  be rejected statically: voice would ask for a scope auth does not know and
  every token request would fail with `invalid_scope`.
- Per-member approval by the component owner (`core_owner`, `identity_owner`,
  `support_platform_owner`, `agent_owner`) plus one set approval of the set
  digest S; changing any member invalidates the set approval.
- Evidence matrix: `test.suite_each` per member, `test.contract` showing the
  measured diffs are additive (matching the declaration), `test.integration`
  bound to S.
- After the lost merge answer: the run reconciles the kervan-mcp member from the
  PR state (merged), records it as applied, and does not merge it twice; voice
  and evals are only merged after that.
- The flaky CI run appears as a failed, then a passed run of the same commit;
  only the attested passing run satisfies the criterion.

## Reference notes

- Scope lists to extend: `kervan-auth/src/config.ts` (`SCOPES_SUPPORTED`),
  `kervan-mcp/src/config.ts` (`SCOPES`), `kervan-voice/src/auth/metadata.ts`
  (`CLIENT_SCOPES`). The voice agent asks for every scope in its list, so an
  unknown scope breaks all of its tools at once.
- SPEC.md (§3.1, §4, §5) is the shared contract and is updated first.
