"""Regenerates seed/prod_sim/logs/{mcp,core}.jsonl from prod_sim's seeded rows.

An authoring tool, not part of bringing an environment up. Run it after a change
to seed/prod_sim.sql, on a freshly seeded prod_sim, on the same day:

    scripts/down.sh prod_sim --volumes && scripts/up.sh prod_sim
    python seed/prod_sim/generate-logs.py

It reads the rows through `docker exec <postgres container> psql`, simulates a
week of customer-agent traffic that agrees with them (every successful
reschedule is a "Delivery rescheduled" event, every agent ticket a ticket row,
the incident's 409s hit exactly the affected parcels) and writes timestamps as
templates ({{today-N}}T…Z) that seed/init-logs.sh expands. The pseudo-random
choices use a fixed seed, so the same rows give the same files. Logs carry no
personal data (SPEC §6).
"""
import datetime as dt
import json
import os
import random
import subprocess
import sys
import uuid
from zoneinfo import ZoneInfo

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
CONTAINER = os.environ.get("KERVAN_PG_CONTAINER", "kervan-prod_sim-postgres-1")
IST = ZoneInfo("Europe/Istanbul")
UTC = dt.timezone.utc
rng = random.Random(20261010)


def q(sql):
    out = subprocess.run(
        ["docker", "exec", CONTAINER, "psql", "-U", "kervan_core", "-d", "kervan",
         "-At", "-F", "\t", "-c", "set time zone 'UTC'", "-c", sql],
        check=True, capture_output=True, text=True, encoding="utf-8").stdout
    return [line.split("\t") for line in out.splitlines() if line and line != "SET"]


def ts(s):
    return dt.datetime.fromisoformat(s.replace(" ", "T")).astimezone(UTC)


today = dt.datetime.now(IST).date()
batch_at = dt.datetime.combine(today - dt.timedelta(days=3), dt.time(2, 13, 7), UTC)

ships = {}
for no, dest, created, status, ddate, dstatus in q(
        "select s.tracking_no, s.destination_city, s.created_at, s.status, d.delivery_date, d.status "
        "from shipments s join deliveries d using (tracking_no)"):
    ships[no] = dict(dest=dest, created=ts(created), status=status,
                     ddate=dt.date.fromisoformat(ddate), dstatus=dstatus)
incident = {r[0] for r in q(
    f"select tracking_no from shipment_events where at = '{batch_at.isoformat()}'")}
resched = [(r[0], ts(r[1])) for r in q(
    "select tracking_no, at from shipment_events where description like 'Delivery rescheduled%'")]
tickets = [(r[0], r[1] or None, r[2], r[3], ts(r[4])) for r in q(
    "select ticket_id, tracking_no, category, channel, created_at from tickets")]
delivered_at = {r[0]: ts(r[1]) for r in q(
    "select tracking_no, max(at) from shipment_events where description = 'Delivered' group by 1")}

mcp, core = [], []


def trace():
    return str(uuid.UUID(int=rng.getrandbits(128), version=4))


def stamp(t):
    return t.strftime("%Y-%m-%dT%H:%M:%S.") + f"{t.microsecond // 1000:03d}Z"


def line(store, t, level, service, msg, **fields):
    store.append((t, {"ts": stamp(t), "level": level, "service": service, "msg": msg, **fields}))


def tool(t, name, status, method, path, trace_id=None, mcp_level=None):
    """One tool call: core's access line, then mcp's tool line a few ms later."""
    trace_id = trace_id or trace()
    core_ms = rng.randint(2, 30)
    core_t = t + dt.timedelta(milliseconds=core_ms)
    lvl = "error" if status >= 500 else "warn" if status >= 400 else "info"
    if path is not None:
        line(core, core_t, lvl, "core", f"{method} {path}", trace_id=trace_id, status=status, duration_ms=core_ms)
    mcp_t = core_t + dt.timedelta(milliseconds=rng.randint(1, 4))
    dur = int((mcp_t - t).total_seconds() * 1000)
    if status < 400:
        line(mcp, mcp_t, "info", "mcp", "tool call", trace_id=trace_id, tool=name, status=status, duration_ms=dur)
    else:
        line(mcp, mcp_t, mcp_level or lvl, "mcp", "tool call failed", trace_id=trace_id, tool=name, status=status,
             duration_ms=dur)
    return mcp_t


def business_time(day, start_h=6, end_h=18):
    sec = rng.randint(start_h * 3600, end_h * 3600 + 1799)
    return dt.datetime.combine(day, dt.time(), UTC) + dt.timedelta(seconds=sec, milliseconds=rng.randint(0, 999))


def get_path(no):
    return f"/api/v1/shipments/{no}"


days = [today - dt.timedelta(days=d) for d in range(7, 0, -1)]

# Successful reschedules: exactly the "Delivery rescheduled" events core appended.
for no, at in resched:
    tool(at - dt.timedelta(milliseconds=rng.randint(3, 9)), "reschedule_delivery", 200, "POST", get_path(no) + "/reschedule")

# Tickets opened by the agent: the "late" flow looks the parcel up first.
for tid, no, cat, channel, at in tickets:
    if channel != "agent":
        continue
    tr = trace()
    start = at - dt.timedelta(milliseconds=rng.randint(15, 40))
    if cat == "DELAY":
        tool(start - dt.timedelta(milliseconds=30), "get_shipment", 200, "GET", get_path(no), trace_id=tr)
    tool(start, "open_ticket", 201, "POST", "/api/v1/tickets", trace_id=tr)

for day in days:
    open_at = dt.datetime.combine(day, dt.time(), UTC)
    known = [no for no, s in ships.items() if s["created"] < open_at]
    # Status lookups.
    for _ in range(rng.randint(42, 58)):
        tool(business_time(day), "get_shipment", 200, "GET", get_path(rng.choice(known)))
    # Mistyped tracking numbers.
    for _ in range(rng.randint(2, 4)):
        tool(business_time(day), "get_shipment", 404, "GET", get_path(f"KRV3{rng.randint(1000, 99999):07d}"))
    # Help questions.
    for _ in range(rng.randint(8, 13)):
        tool(business_time(day), "search_help", 200, None, None)
    # Reschedule attempts that fail for ordinary reasons.
    movable = [no for no in known if ships[no]["ddate"] > day + dt.timedelta(days=1) and no not in incident
               and ships[no]["status"] in ("IN_TRANSIT", "CREATED")]
    for _ in range(rng.randint(1, 3)):
        tool(business_time(day), "reschedule_delivery", 403, "POST", get_path(rng.choice(movable)) + "/reschedule")
    for _ in range(rng.randint(0, 2)):
        tool(business_time(day), "reschedule_delivery", 400, "POST", get_path(rng.choice(movable)) + "/reschedule")
    done = [no for no, at in delivered_at.items() if at < open_at]
    for _ in range(rng.randint(0, 1) if done else 0):
        tool(business_time(day), "reschedule_delivery", 409, "POST", get_path(rng.choice(done)) + "/reschedule")

# The incident: from the morning after the batch, reschedule attempts for the
# affected Bursa parcels whose delivery is still ahead fail with 409.
stuck = sorted(no for no in incident if ships[no]["status"] == "OUT_FOR_DELIVERY" and ships[no]["ddate"] > today)
for no in stuck:
    for _ in range(rng.choice([1, 1, 2, 2, 3])):
        day = rng.choice(days[-3:])
        tr = trace()
        t = business_time(day, start_h=6 if day > days[-3] else 3)
        if rng.random() < 0.5:  # the agent sometimes looks the parcel up first
            t = tool(t, "get_shipment", 200, "GET", get_path(no), trace_id=tr) + dt.timedelta(milliseconds=40)
        tool(t, "reschedule_delivery", 409, "POST", get_path(no) + "/reschedule", trace_id=tr)

# Noise: a short kervan-search restart (today-5) and an auth restart (today-4).
outage = dt.datetime.combine(days[1], dt.time(10, 41, 3), UTC)
for i in range(5):
    t = outage + dt.timedelta(seconds=22 * i, milliseconds=rng.randint(0, 999))
    line(mcp, t, "error", "mcp", "upstream unavailable", trace_id=trace(), tool="search_help",
         duration_ms=rng.randint(1, 4), reason="fetch failed")
restart = dt.datetime.combine(days[2], dt.time(7, 2, 11), UTC)
for i in range(3):
    t = restart + dt.timedelta(seconds=3 * i, milliseconds=rng.randint(0, 999))
    line(mcp, t, "warn", "mcp", "token rejected", trace_id=trace(), status=401, reason="ERR_JWKS_NO_MATCHING_KEY")
# One database hiccup in core (today-2).
hiccup = dt.datetime.combine(days[4], dt.time(14, 3, 37), UTC)
tr = trace()
line(core, hiccup, "error", "core", "request failed: CannotGetJdbcConnectionException", trace_id=tr)
tool(hiccup - dt.timedelta(milliseconds=5), "get_shipment", 500, "GET", get_path(rng.choice(list(ships))), trace_id=tr)


def template(t):
    n = (today - t.date()).days
    assert 0 < n < 20, t
    return f"{{{{today-{n}}}}}" + stamp(t)[10:]


for name, store in (("mcp", mcp), ("core", core)):
    store.sort(key=lambda x: x[0])
    with open(f"{OUT}/{name}.jsonl", "w", encoding="utf-8", newline="\n") as f:
        for t, entry in store:
            assert t.hour < 21, entry  # the UTC date is the Istanbul date
            entry["ts"] = template(t)
            f.write(json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(name, len(store))
print("stuck parcels", len(stuck), "incident", len(incident))
