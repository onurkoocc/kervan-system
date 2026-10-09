# Kervan design task set

The open **design** set of brownfield tasks (design doc 9 §10.3). Mandate's
brownfield features (BACKLOG items 29–37) are designed and tried against these.
Gate 5's task set is generated from the same eight classes.

**The sealed, hidden evaluation set is not here.** Doc 9 §10.4 (proposal Ö4)
asks for a second set written by an independent session, committed only as
hashes and kept apart until Gate 5 starts. That decision is still pending (Ö4,
BACKLOG §2), so no evaluation tasks exist yet. Do not add any here: anything in
this directory is, by definition, design material.

## Tasks

| Id | Class | Title | Components | Environment, mode |
|---|---|---|---|---|
| [KD-01](KD-01-delivery-window.md) | 1 cross feature | Let customers change the delivery window through the agent | core, auth, mcp, voice, evals, system | staging, live |
| [KD-02](KD-02-reschedule-scope.md) | 2 breaking evolution | Split `deliveries:write` into a narrower `deliveries:reschedule` scope | auth, mcp, voice | staging, live |
| [KD-03](KD-03-audience-mismatch.md) | 3 boundary bug | Accept tokens for the MCP server as a whole (the `aud` trap) | mcp (auth, voice unchanged) | staging, live |
| [KD-04](KD-04-window-column.md) | 4 data migration | Rename `deliveries."window"` to `time_window` with a backfill | core, system | staging live; prod_sim design |
| [KD-05](KD-05-bursa-incident.md) | 5 read-only incident | Why can Bursa customers not move their deliveries? | — (reads core, mcp) | prod_sim, read_only |
| [KD-06](KD-06-jose-advisory.md) | 6 dependency patch | Patch `jose` in every TypeScript repository | auth, mcp, voice | staging, live |
| [KD-07](KD-07-warmer-agent.md) | 7 agent regression | Warmer replies and "the day after tomorrow" | voice, evals | staging, live |
| [KD-08](KD-08-model-drift.md) | 8 drift | Find where the system model and the repositories disagree | system (reads all) | design, read_only |
| [KD-09](KD-09-affected-customers.md) | 5 read-only (data class) | A call list of the customers the Bursa incident hit | — (reads core) | prod_sim, read_only |
| [KD-10](KD-10-shipment-delivery-object.md) | 2 breaking evolution | Replace `estimatedDelivery` with a `delivery` object in core's API | core, voice (mcp passes through) | staging, live |

## File format

Each task is one Markdown file with a YAML header:

```yaml
id: KD-01
class: 1                  # doc 9 §10.3, 1–8
title: …
components: [core, mcp]   # component names of system/kervan.system.mdt
interfaces:               # every interface the change touches, with the declared kind
  - {name: CoreApi, change: additive}     # additive | breaking | none
environment: staging      # dev | staging | prod_sim
mode: live                # design | read_only | live (doc 9 §5.2)
faults:                   # injected by the harness; doc 9 §10.3
  - {kind: unknown_outcome_at_merge, at: "…"}
```

Fault kinds: `unknown_outcome_at_merge` (the merge call's outcome is lost; the
run must reconcile from the PR state), `flaky_ci` (a CI run fails once for a
reason unrelated to the change), `stale_evidence` (evidence for an older commit
or set digest is offered), `budget_exhaustion` (the run's budget is set so it
runs out at the named point).

The body has four parts: **Request** (as a person would write it, with no hint
of the solution), **Acceptance criteria**, **Faults to inject**, and **What
Mandate must show** (the properties the run, its journal and its views must
exhibit). Some tasks add **Reference notes** for whoever stages the task; they
are not part of the request.

## Staging a task

- Base commits: the `seed` tag of every Kervan repository (SPEC: `publish.sh`).
- Environments: `scripts/up.sh <env>`; integration evidence: `scripts/e2e.sh`
  with `KERVAN_SRC` pointing at the candidate working copies.
- Model calls follow K10/K14/K40: single agent and a low run limit for
  development trials; ask before exceeding a cap.
