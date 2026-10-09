# Seed data

What each Kervan environment holds. The compose service `seed`
(`seed/apply.sh`) applies it once core is healthy, which means Flyway has
migrated the schema:

1. `roles.sql`, in every environment: the read-only login role
   `kervan_reader` (password `kervan_reader`) with `select` on
   `v_shipment_overview`, `tickets` and `shipment_events` and nothing else
   (SPEC §5.1). Its sessions are also read-only by default. This is the role
   Mandate's read broker uses.
2. `<KERVAN_ENV>.sql`, in one transaction. `dev` and `staging` are reset to
   their fixtures on every run. `prod_sim` is seeded only into an empty
   database, like a production that is never reseeded.

The compose service `logs-init` (`seed/init-logs.sh`) runs before every other
service. It makes the shared log directory writable for each service's uid and,
for prod_sim, copies the pre-baked logs in, once.

All data is synthetic. Dates are relative to today in Europe/Istanbul, core's
clock zone, so an environment built on any day tells the same story. Phone
numbers use the unassigned `+90 500` prefix, e-mail addresses the reserved
`.test` domain. The SQL respects core's schema: `deliveries."window"` is
quoted, enum columns hold only allowed values, and ticket numbers stay below
`TCK-100001`, where core's sequence starts.

## dev (`dev.sql`)

Six hand-written shipments for trying things by hand. The verification code
is the last four digits of the phone.

| Tracking number | State | Code |
|---|---|---|
| `KRV20000001` | in transit, İstanbul → Ankara, delivery today+2 | 1234 |
| `KRV20000002` | in transit, İzmir → Bursa, delivery today+4 | 5678 |
| `KRV20000003` | out for delivery today (409 on reschedule) | 9012 |
| `KRV20000004` | delivered yesterday | 3344 |
| `KRV20000005` | created, not picked up, delivery today+6 | 2468 |
| `KRV20000006` | returned to sender | 7701 |

## staging (`staging.sql`)

The fixed data the scenarios assume.

- `KRV10000001`–`KRV10000008` match the table in
  `kervan-voice-evals/scenarios/README.md` exactly: status, delivery row and
  the last four digits of the phone. `KRV99999999` does not exist.
- `KRV10000101`–`KRV10000104` belong to the end-to-end scenarios in
  `../e2e/scenarios`, so the two suites never share a parcel:

  | Tracking number | Used by | State | Code |
  |---|---|---|---|
  | `KRV10000101` | `e2e-status-lookup` | in transit, İstanbul → Ankara, delivery today+3 | 0101 |
  | `KRV10000102` | `e2e-reschedule-then-status` | in transit, delivery today+6 | 3307 |
  | `KRV10000103` | `e2e-damaged-parcel-ticket` | delivered yesterday | 0303 |
  | `KRV10000104` | `e2e-out-for-delivery-refused` | out for delivery today | 9054 |

Every event lies in the past, so an event core appends (after a reschedule) is
always a shipment's latest.

## prod_sim (`prod_sim.sql`, `prod_sim/logs/`)

Kervan's simulated production, the environment of the read-only design tasks
(KD-05, KD-09).

- **200 customers** with `confidential` names, phones and e-mails; 200
  distinct names from common Turkish given names and surnames.
- **500 shipments** `KRV30000001`–`KRV30000500` across 15 cities (13 as
  destinations, weighted towards İstanbul, Ankara, İzmir and Bursa), with
  deliveries from today−6 to today+8, their events (created, picked up,
  departed, arrived, out for delivery, delivered, failed attempts, returns,
  reschedules) and **54 tickets**.
- The rows come from a deterministic generator: plain arithmetic (a
  multiplicative hash) on the row number, with no `random()`. Every build
  holds the same rows.
- **Logs:** `prod_sim/logs/mcp.jsonl` and `core.jsonl`, a week of history in
  the SPEC §6 format, with no personal data. Timestamps are templates
  (`{{today-N}}T08:12:44.120Z`) that `init-logs.sh` expands. The files land in
  `$KERVAN_DATA/prod_sim/logs` on the host (default `kervan-system/data`),
  where the read broker reads them, and the running services append to them.
- **Read replica:** PostgreSQL on `127.0.0.1:55432`, role `kervan_reader`.

### The embedded incident

At **today−3, 02:13:07 UTC** a route-planning batch, which is not part of
core and writes to the database directly, marked every Bursa shipment already
booked with a delivery from today−2 on as `OUT_FOR_DELIVERY`, and appended an
"Out for delivery" event with that one instant to each. Thirty of them still
have their delivery 1 to 8 days ahead. Core refuses to reschedule a shipment
that is out for delivery, so since that morning every reschedule request for
those parcels fails with `409 not_reschedulable`, and the agent tells
customers their parcel "is out for delivery today".

No single source shows it:

- **mcp's log** shows the refusals: `reschedule_delivery` with status 409
  goes from one in the four days before to 17–20 a day since, while other
  cities' reschedules keep succeeding. mcp logs tool names and trace ids,
  never arguments, so the lines carry no tracking number. These lines are at
  level `warn`.
- **core's log** has the request lines with the same trace ids:
  `POST /api/v1/shipments/KRV300…/reschedule`, status 409. They give the
  tracking numbers.
- **The replica** explains them. `v_shipment_overview` shows those parcels
  going to Bursa, `OUT_FOR_DELIVERY`, with a delivery date days ahead.
  `shipment_events` shows the shared instant, often before the parcel had
  even left its origin. `tickets` shows the complaints since then: agent
  `DELAY` tickets with "Current status: OUT_FOR_DELIVERY", and phone and web
  tickets saying the date cannot be changed.
- No core log line changes a status: the writer is outside core.

Red herrings in the same window: a kervan-search restart (today−6, five mcp
`upstream unavailable` errors), an auth key rotation (today−5, three mcp
`token rejected` warnings), and one core database hiccup (today−3 14:03 UTC,
one 500). The system model's `mcp_errors` read selects `level == "error"` and
therefore sees only these, not the 409s; `core_warnings` does.

### Changing prod_sim

The logs were generated from the rows. After changing `prod_sim.sql`,
regenerate them on a freshly seeded prod_sim:

```sh
scripts/down.sh prod_sim --volumes && scripts/up.sh prod_sim
python seed/prod_sim/generate-logs.py
```
