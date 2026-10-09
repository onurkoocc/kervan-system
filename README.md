# kervan-system

The seventh repository of **Kervan**, the fictional cargo and delivery company
that Mandate's brownfield work is built and measured on (design doc 9 §10). It
owns no service. It holds what ties the six service repositories into one
system:

- **the system model:** `system/kervan.system.mdt`, a Mandate module with the
  components, the interfaces between them and the environments they run in;
- **the environments:** compose files that build every service from its
  repository, and the seed data of `dev`, `staging` and `prod_sim`;
- **the end-to-end scenarios** that Mandate's `test.integration` runs;
- **the design task set** (doc 9 §10.3).

All data is synthetic. The cross-repository contract is `SPEC.md` (in the
Mandate repository, `examples/kervan/SPEC.md`); this repository implements its
§10.

```text
kervan-system/
  system/kervan.system.mdt      the system model (changing it is a governance change)
  compose/base.yml              every service, built from ${KERVAN_SRC:-../..}/kervan-<name>
  compose/dev.yml               ports on 127.0.0.1, seed dev
  compose/staging.yml           fixed seed staging
  compose/prod_sim.yml          confidential seed, read replica on 127.0.0.1:55432, logs on the host
  compose/integration.yml       test.integration: internal network, no ports, the e2e runner
  seed/                         roles.sql, dev.sql, staging.sql, prod_sim.sql, prod_sim/logs (seed/README.md)
  e2e/scenarios/                end-to-end scenarios (kervan-voice-evals format)
  scripts/up.sh, down.sh        bring an environment up / down
  scripts/e2e.sh                staging + integration under a fresh project, run e2e, tear down
  tasks/                        the design task set (tasks/README.md)
```

## Requirements

Docker with BuildKit and Compose v2.24 or later (`integration.yml` uses
`!reset`). Bash for the scripts; on Windows, Git Bash works (the scripts pass
`C:/…` paths to Docker and set `MSYS_NO_PATHCONV=1`). The service repositories
sit next to this one:

```text
kervan/
  kervan-auth/  kervan-core/  kervan-mcp/  kervan-search/  kervan-voice/  kervan-voice-evals/
  kervan-system/      ← here
```

## Environments

| | dev | staging | prod_sim |
|---|---|---|---|
| Purpose | a developer's own system | the scenarios run here; integration evidence | Kervan's "production": read-only tasks, read broker |
| Data class (model) | `internal` | `internal` | `confidential` |
| Seed | 6 hand-written shipments, reset on every `up` | the evals' tracking numbers + the e2e ones, reset on every `up` | 200 customers, 500 shipments, an embedded incident; seeded once |
| Published | every service on 127.0.0.1 (7000, 9000, 3001, 8080, 8001; postgres 5432) | nothing | postgres on 127.0.0.1:55432, for role `kervan_reader` only |
| Logs | volume | volume | host directory `$KERVAN_DATA/prod_sim/logs` |
| Writes | anyone | Mandate, with `deploy` and `migrate` authorized by policy | only the CD adapter; `deploy` by `release_manager`, `migrate` by `db_owner` |

Each environment is the six services (`postgres`, `core`, `auth`, `search`,
`mcp`, `voice`) wired exactly as SPEC §2 says. Two one-shot services surround
them. `logs-init` prepares the shared log directory before anything starts.
`seed` waits until core is healthy, which means Flyway has migrated, then
creates `kervan_reader` and applies `seed/<env>.sql`. Every service has a
healthcheck and starts only when what it depends on is healthy. What each seed
holds, and the incident in prod_sim, is in [`seed/README.md`](seed/README.md).

## Running

```sh
scripts/up.sh dev                 # build, start, wait for healthy + seeded (~15 s when the images are cached)
curl -s localhost:7000/converse -H 'content-type: application/json' \
     -d '{"conversation_id":"c1","utterance":"Where is my parcel KRV20000001?"}'
scripts/down.sh dev               # stop; add --volumes to drop the database and logs

scripts/up.sh prod_sim
docker run --rm postgres:16 psql postgresql://kervan_reader:kervan_reader@host.docker.internal:55432/kervan \
     -c 'select tracking_no, status, destination_city, delivery_date from v_shipment_overview limit 5'
scripts/down.sh prod_sim --volumes   # also removes $KERVAN_DATA/prod_sim

scripts/e2e.sh                    # exit code = the scenario result
```

The scripts use the compose project `kervan-<env>`; `e2e.sh` uses a fresh
`kervan-e2e-<time>-<pid>` each time and removes it, with its volumes,
afterwards. Plain compose works too, from `compose/`:

```sh
docker compose -p kervan-staging -f base.yml -f staging.yml up -d --build
```

| Variable | Default | Meaning |
|---|---|---|
| `KERVAN_SRC` | `../..` from `compose/` (the siblings of this repository) | Directory holding the `kervan-*` working copies to build |
| `KERVAN_TAG` | `local` (`e2e.sh`: `src-<hash of KERVAN_SRC>` when `KERVAN_SRC` is set) | Tag of the built images `kervan-<name>:<tag>` |
| `KERVAN_DATA` | `kervan-system/data` | Host directory for prod_sim's logs and the e2e reports (git-ignored) |
| `KERVAN_ENV` | set by each overlay | Which seed `seed` applies |
| `KERVAN_DEV_PG_PORT` | `5432` | dev's published PostgreSQL port |
| `KERVAN_WAIT_SECONDS` | `300` | How long the scripts wait for healthy services |
| `E2E_KEEP` | unset | `1`: `e2e.sh` leaves the environment running |

Timings on the reference machine (Windows 11, Docker Desktop 29): building
all six images from scratch, with no BuildKit cache and base images present,
takes about 3.5 minutes. With cached images, `scripts/up.sh` takes about
15 seconds and `scripts/e2e.sh` about 20 seconds, of which the scenarios take
2 seconds.

## End-to-end scenarios and test.integration

`e2e/scenarios/*.yaml` use the kervan-voice-evals format and run with its
image. They drive the whole chain on staging data: voice gets a token from
auth (CIMD, `private_key_jwt`), calls mcp, mcp checks the token against auth's
JWKS and calls core or search:

| Scenario | Path through the system |
|---|---|
| `e2e-status-lookup` | `get_shipment` → core; the reply carries the seeded route and date |
| `e2e-reschedule-then-status` | `reschedule_delivery` → core writes, then `get_shipment` reads the new date and the appended event back |
| `e2e-out-for-delivery-refused` | core's 409 `not_reschedulable` through mcp's error mapping to the agent |
| `e2e-damaged-parcel-ticket` | `open_ticket` → core assigns a `TCK-` id |
| `e2e-help-search` | `search_help` → kervan-search |

They catch what each repository's own tests and the contract diffs cannot
see. If kervan-mcp starts expecting a different token audience than
kervan-auth issues (design task KD-03), mcp's unit tests and every spec file
stay green, while every scenario fails with `tool_unavailable` and mcp logs
`token rejected … "reason":"aud_mismatch"`. `e2e.sh` prints those log lines
next to the failed checks.

`compose/integration.yml` is the overlay of Mandate's `test.integration` (doc
9 §4.5, K43). The default network is `internal: true`, so no container has
egress and nothing is published, and the `e2e` service exits 0 or 1. Mandate
points `KERVAN_SRC` at the candidate working copies of a change set and runs:

```sh
KERVAN_SRC=/work scripts/e2e.sh
```

Every service, and the scenario runner, is then built from the candidates.
Each service's Dockerfile fetches dependencies from its lock file only and
compiles with `--network=none` (SPEC §11), so candidate code never runs with
network.

## How Mandate uses the model

`system/kervan.system.mdt` is a module, `kervan.system`. Programs import from
it what they work on, for example `use kervan.system.{mcp, core, CoreApi, prod_sim}`,
and the lock file pins it by hash, so a run's system model never changes under
it.

- **Components** name each repository, its working root in the sandbox, its
  owner role and its `build` and `test` commands. Capabilities on a component
  expand to that repository's paths and commands. `test.suite_each` runs each
  member's tests.
- **Interfaces** name the spec file in the provider's repository (OpenAPI, MCP
  tool list, OAuth metadata, migrations). `test.contract` diffs those files
  between base and candidate and compares the measured change kind with the
  plan's declaration (`additive`, `breaking`, `none`). The `provides` and
  `consumes` relations give the order of a change set.
- **Environments** carry their data class, the reads the read broker may run
  (declared, parameterized SQL on the replica as `kervan_reader`, and log
  queries over `$KERVAN_DATA/prod_sim/logs`; model output is only ever a
  parameter), and the authorization tier for `deploy` and `migrate`.
- Changing the model is a governance change. Design task KD-08 is about the
  model drifting from the code.

## CI

`.github/workflows/ci.yml` checks out the six sibling repositories next to
this one. On every push it validates every compose combination
(`docker compose config`) and checks the shell scripts. The `e2e` job is
manual (`workflow_dispatch`), because it builds every image: it brings
staging up under `integration.yml`, which also proves the seed SQL, and runs
the scenarios. The sibling repositories are private, so checking them out
needs a read token in the secret `KERVAN_REPOS_TOKEN`.
