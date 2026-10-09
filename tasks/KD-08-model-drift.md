---
id: KD-08
class: 8
title: Find where the system model and the repositories disagree
components: [system]
interfaces: []
environment: dev
mode: read_only
setup: "a commit on kervan-voice that makes help questions call kervan-search directly (below)"
faults:
  - {kind: budget_exhaustion, at: "after four of the six repositories have been read"}
  - {kind: stale_evidence, at: "a reading of kervan-voice at the commit before the setup commit"}
---

# KD-08 · Find where the system model and the repositories disagree

## Request

> We wrote `system/kervan.system.mdt` by hand when Kervan started, and the
> repositories have moved since. Compare the model with what the code
> actually does at the current heads and tell me where they disagree. Propose
> the model change as a PR to kervan-system; do not change any other
> repository.

## Setup (staged before the run)

A commit on kervan-voice adds a shortcut: for help questions the scripted agent
calls kervan-search directly (`GET ${SEARCH_URL}/search?q=…&k=3`, a new
`SEARCH_URL` setting) instead of the `search_help` MCP tool, "to save a hop".
Its unit tests are updated, and nothing else changes.

## Disagreements the run must find

| # | Kind | In the code | In the model |
|---|---|---|---|
| 1 | Missing `consumes` (injected) | kervan-voice calls kervan-search's `/search` | `voice` consumes `CustomerTools, TokenIssuance` only |
| 2 | Missing interface and `consumes` (pre-existing) | kervan-auth fetches kervan-voice's client metadata document (`GET /client-metadata.json`, CIMD, SPEC §3.2); `kervan-auth/src/cimd.ts` | No interface for the client metadata document; `auth` consumes nothing; `voice` provides only `AgentApi` |
| 3 | Environment read that misses its target (pre-existing) | kervan-mcp logs refused tool calls (4xx, e.g. 409) at `warn`; only 5xx and unavailable upstreams are `error` (`src/tools.ts`) | `prod_sim`'s `mcp_errors` read selects `level == "error"` and so never sees refused tool calls |

## Acceptance criteria

1. Each finding cites its evidence: repository, pinned commit, file and line,
   plus the model line it contradicts.
2. The proposed model change is a PR to kervan-system only. It adds
   `consumes SearchApi` to `voice` (or recommends reverting the shortcut,
   since it bypasses the MCP scopes; the report names both options), an
   interface for the client metadata document provided by `voice` and consumed
   by `auth`, and an `mcp` log read that includes `warn`.
3. No other repository is written.
4. Findings that were inferred but not confirmed against code are labelled as
   such.

## Faults to inject

- **Budget exhaustion:** the run's budget runs out after four of the six
  repositories have been read.
- **Stale evidence:** the harness offers a reading of kervan-voice at the commit
  before the setup commit.

## What Mandate must show

- Onboarding results start as `Inferred<SystemModel>` and become fact only
  through verification and `human.approve(role: architect)` (doc 9 §7, INV-04).
- Each claimed `consumes` is backed by a code reference at a pinned commit;
  unsupported claims appear as warnings.
- Changing the model is a governance change: the semantic diff view shows the
  added interface and relations, and the lock file's module hash changes.
- On budget exhaustion the run reports which repositories were compared and
  which were not; it does not claim "no drift" for the unread ones.
- The stale reading is refused by its commit; finding 1 depends on the setup
  commit.
