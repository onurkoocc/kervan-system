-- prod_sim: Kervan's simulated production. Applied by seed/apply.sh in one
-- transaction after core's migrations, only into an empty database.
--
-- 200 customers, 500 shipments across Turkish cities, their deliveries and
-- events, and tickets. Everything comes from a deterministic generator (plain
-- arithmetic on the row number, no random()), so every build holds the same
-- rows; dates are relative to today in Europe/Istanbul, core's clock zone.
--
-- customers.full_name, phone and email are confidential (SPEC §5.2). They are
-- synthetic: names are combinations of common given names and surnames, phones
-- use the unassigned +90 500 prefix, e-mails the reserved .test domain.
--
-- The embedded incident (design task class 5; see seed/README.md): at
-- today-3 02:13:07 UTC a faulty route-planning batch marked every Bursa
-- shipment whose delivery was still ahead as OUT_FOR_DELIVERY and appended an
-- "Out for delivery" event with that same instant. Since then those parcels
-- cannot be rescheduled (core answers 409 not_reschedulable). The history in
-- seed/prod_sim/logs/*.jsonl was generated from these rows; change one, regenerate the other.

set time zone 'Europe/Istanbul';
select current_date as today \gset
select ((:'today'::date - 3) + time '02:13:07') at time zone 'UTC' as batch_at \gset

-- ── Reference lists ──────────────────────────────────────────────────────────
create temp table city (n int primary key, name text not null) on commit drop;
insert into city values
  (0, 'İstanbul'), (1, 'Ankara'), (2, 'İzmir'), (3, 'Bursa'), (4, 'Antalya'),
  (5, 'Konya'), (6, 'Adana'), (7, 'Gaziantep'), (8, 'Kayseri'), (9, 'Eskişehir'),
  (10, 'Trabzon'), (11, 'Samsun'), (12, 'Mersin'), (13, 'Diyarbakır'), (14, 'Denizli');

-- Where customers live: 20 equal buckets, so bigger cities get more of them.
create temp table home_bucket (b int primary key, city int not null) on commit drop;
insert into home_bucket values
  (0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 1), (6, 1), (7, 2), (8, 2), (9, 3),
  (10, 3), (11, 4), (12, 5), (13, 6), (14, 7), (15, 8), (16, 9), (17, 10), (18, 11), (19, 12);

create temp table given_name (n int primary key, name text not null, slug text not null) on commit drop;
insert into given_name values
  (0, 'Ayşe', 'ayse'), (1, 'Mehmet', 'mehmet'), (2, 'Zeynep', 'zeynep'), (3, 'Mustafa', 'mustafa'),
  (4, 'Elif', 'elif'), (5, 'Ahmet', 'ahmet'), (6, 'Fatma', 'fatma'), (7, 'Emre', 'emre'),
  (8, 'Selin', 'selin'), (9, 'Burak', 'burak'), (10, 'Deniz', 'deniz'), (11, 'Can', 'can'),
  (12, 'Ece', 'ece'), (13, 'Kerem', 'kerem'), (14, 'Merve', 'merve'), (15, 'Oğuz', 'oguz'),
  (16, 'Seda', 'seda'), (17, 'Tolga', 'tolga'), (18, 'Yasemin', 'yasemin'), (19, 'Hakan', 'hakan');

create temp table surname (n int primary key, name text not null, slug text not null) on commit drop;
insert into surname values
  (0, 'Yılmaz', 'yilmaz'), (1, 'Kaya', 'kaya'), (2, 'Demir', 'demir'), (3, 'Şahin', 'sahin'),
  (4, 'Çelik', 'celik'), (5, 'Yıldız', 'yildiz'), (6, 'Aydın', 'aydin'), (7, 'Öztürk', 'ozturk'),
  (8, 'Arslan', 'arslan'), (9, 'Doğan', 'dogan'), (10, 'Kılıç', 'kilic'), (11, 'Aslan', 'aslan'),
  (12, 'Kurt', 'kurt'), (13, 'Özdemir', 'ozdemir'), (14, 'Polat', 'polat'), (15, 'Aksoy', 'aksoy'),
  (16, 'Tekin', 'tekin'), (17, 'Güneş', 'gunes'), (18, 'Ateş', 'ates'), (19, 'Bulut', 'bulut');

-- ── Customers (confidential) ─────────────────────────────────────────────────
-- 200 distinct names: given name i mod 20, surname (7·(i div 20) + 3i) mod 20.
insert into customers (id, full_name, phone, email, city)
select i,
       g.name || ' ' || s.name,
       format('+90 500 %s %s %s', 200 + i, substr(code, 1, 2), substr(code, 3, 2)),
       format('%s.%s.%s@example.test', g.slug, s.slug, lpad(i::text, 3, '0')),
       c.name
from generate_series(1, 200) as i
cross join lateral (select lpad(((i * 7919 + 1237) % 10000)::text, 4, '0') as code) as phone
join given_name g on g.n = i % 20
join surname s on s.n = (7 * (i / 20) + 3 * i) % 20
join home_bucket h on h.b = (i * 13) % 20
join city c on c.n = h.city;
select setval(pg_get_serial_sequence('customers', 'id'), 200);

-- ── Shipments and deliveries ─────────────────────────────────────────────────
-- Knuth's multiplicative hash spreads the row number over the choices, so the
-- customer, the delivery day and the origin are independent of each other.
-- off: the delivery date relative to today, from -6 to +8.
create temp table plan on commit drop as
select n,
       'KRV3' || lpad(n::text, 7, '0') as tracking_no,
       (1 + ((n * 2246822519 + 3266489917) % 4294967296) / 65536 % 200)::int as customer_id,
       (((n * 2654435761) % 4294967296) / 65536 % 15 - 6)::int as off,
       (((n * 3266489917 + 668265263) % 4294967296) / 65536 % 15)::int as origin_pick
from generate_series(1, 500) as n;

alter table plan add column destination text, add column origin text, add column base_status text,
                 add column status text, add column delivery_status text, add column attempts int,
                 add column created_at timestamptz, add column incident boolean;

update plan p set destination = c.city from customers c where c.id = p.customer_id;

update plan p set origin = case when o1.name <> p.destination then o1.name else o2.name end
from city o1, city o2
where o1.n = p.origin_pick and o2.n = (p.origin_pick + 1) % 15;

-- Status as it would be without the incident.
update plan set base_status = case
  when off < 0 and n % 29 = 0 then 'RETURNED'
  when off < 0 and n % 13 = 0 then 'IN_TRANSIT'          -- a failed attempt; back at the hub, overdue
  when off < 0 then 'DELIVERED'
  when off = 0 then 'OUT_FOR_DELIVERY'
  when n % 5 = 0 and destination <> 'Bursa' then 'CREATED'
  else 'IN_TRANSIT'
end;

update plan set
  delivery_status = case
    when base_status = 'RETURNED' then 'FAILED'
    when base_status = 'IN_TRANSIT' and off < 0 then 'FAILED'
    when base_status = 'DELIVERED' then 'DELIVERED'
    when off > 0 and n % 9 = 0 and base_status <> 'CREATED' then 'RESCHEDULED'
    else 'SCHEDULED'
  end,
  attempts = case
    when base_status = 'RETURNED' then 3
    when base_status = 'IN_TRANSIT' and off < 0 then 1
    when base_status = 'DELIVERED' then 1 + (n % 7 = 0)::int
    else 0
  end,
  -- Future deliveries were booked 5 to 8 days ago, a parcel not yet picked up
  -- yesterday, past ones 2 to 5 days before their delivery.
  created_at = case
    when base_status = 'CREATED' then :'today'::date - 1
    when off > 0 then :'today'::date - 5 - n % 4
    else :'today'::date + off - 2 - n % 4
  end + time '08:00' + ((n * 47) % 600) * interval '1 minute';

-- The incident: the batch caught every Bursa shipment already booked whose
-- delivery was today-2 or later.
update plan set incident = (destination = 'Bursa' and off >= -2 and created_at < :'batch_at'::timestamptz);
update plan set status = case when incident and off > 0 then 'OUT_FOR_DELIVERY' else base_status end;

insert into shipments (tracking_no, customer_id, status, origin_city, destination_city, created_at)
select tracking_no, customer_id, status, origin, destination, created_at from plan order by n;

insert into deliveries (id, tracking_no, delivery_date, "window", status, attempts)
select n, tracking_no, :'today'::date + off, (array['MORNING', 'AFTERNOON', 'EVENING'])[1 + n % 3],
       delivery_status, attempts
from plan order by n;
select setval(pg_get_serial_sequence('deliveries', 'id'), 500);

-- ── Shipment events ──────────────────────────────────────────────────────────
-- Every event lies in the past, so an event core appends is always the latest.
create temp table ev (tracking_no text, at timestamptz, description text) on commit drop;

insert into ev
select tracking_no, created_at, 'Shipment created' from plan
union all
select tracking_no, created_at + interval '5 hours', 'Picked up in ' || origin
from plan where base_status <> 'CREATED'
union all
select tracking_no, created_at + interval '1 day 2 hours', 'Departed ' || origin || ' transfer centre'
from plan where base_status <> 'CREATED'
union all
-- Customers moved their delivery some days after booking; in Bursa before the batch ran.
select tracking_no,
       case when incident then created_at + interval '1 day 3 hours'
            else least(created_at + interval '1 day 3 hours' + ((n / 9) % 6) * interval '1 day',
                       (:'today'::date - 1) + time '17:00' + (n % 60) * interval '1 minute') end,
       'Delivery rescheduled to ' || (:'today'::date + off) || ' at the recipient''s request'
from plan where delivery_status = 'RESCHEDULED'
union all
select tracking_no, (:'today'::date + off - 1) + time '22:30', 'Arrived at ' || destination || ' transfer centre'
from plan where off <= 0
union all
select tracking_no,
       least((:'today'::date + off) + time '08:00' + (n % 90) * interval '1 minute', now() - interval '1 minute'),
       'Out for delivery'
from plan where off <= 0
union all
select tracking_no, (:'today'::date + off) + time '11:00' + ((n * 7) % 300) * interval '1 minute', 'Delivered'
from plan where base_status = 'DELIVERED'
union all
select tracking_no, (:'today'::date + off) + time '18:10' + (n % 40) * interval '1 minute',
       'Delivery attempt failed: recipient not at home'
from plan where delivery_status = 'FAILED'
union all
select tracking_no, (:'today'::date + off) + time '20:05', 'Returned to sender'
from plan where base_status = 'RETURNED'
union all
-- The faulty batch: one instant for every affected parcel.
select tracking_no, :'batch_at'::timestamptz, 'Out for delivery' from plan where incident;

insert into shipment_events (id, tracking_no, at, description)
select row_number() over (order by at, tracking_no, description), tracking_no, at, description from ev;

-- ── Tickets ──────────────────────────────────────────────────────────────────
-- Agent tickets carry kervan-voice's fixed texts; no ticket holds personal data.
create temp table tk (n int, tracking_no text, category text, description text, channel text,
                      created_at timestamptz) on commit drop;

-- Everyday tickets about one shipment in fourteen, on a past day (never later
-- than yesterday), between 09:00 and 19:00. The agent opens only DAMAGED, LOST
-- and DELAY tickets; OTHER ones come from the web form or the phone.
insert into tk
select n, tracking_no, category,
       case
         when channel = 'agent' then case category
           when 'DAMAGED' then 'Customer reports that the parcel arrived damaged. Reported via the customer agent.'
           when 'LOST' then 'Customer reports that the parcel has not been received and may be lost. Reported via the customer agent.'
           else 'Customer reports that the delivery is late. Reported via the customer agent. Current status: ' || base_status || '.' end
         else case category
           when 'DAMAGED' then 'The outer box was dented and one item inside is broken.'
           when 'LOST' then 'A delivery attempt was reported but the parcel never arrived.'
           when 'DELAY' then 'The parcel is later than the estimated delivery date.'
           else 'Asks for a copy of the delivery receipt.' end
       end,
       channel,
       least(created_at::date + 2, :'today'::date - 1) + time '09:00' + ((n * 13) % 600) * interval '1 minute'
from (
  select p.*, c.category,
         case when c.category = 'OTHER' then (array['web', 'phone'])[1 + n % 2]
              else (array['web', 'phone', 'agent'])[1 + n % 3] end as channel
  from plan p
  cross join lateral (select case
           when p.base_status = 'DELIVERED' and (p.n / 14) % 2 = 0 then 'DAMAGED'
           when p.base_status = 'IN_TRANSIT' and p.off < 0 then 'LOST'
           when p.base_status in ('IN_TRANSIT', 'CREATED') then 'DELAY'
           else 'OTHER'
         end as category) as c
  where n % 14 = 3 and not incident
) as t;

-- The incident's tickets: customers whose parcel has "been out for delivery" for days.
insert into tk
select n, tracking_no,
       case when n % 2 = 0 then 'DELAY' else 'OTHER' end,
       case
         when n % 2 = 0 then 'Customer reports that the delivery is late. Reported via the customer agent. Current status: OUT_FOR_DELIVERY.'
         when n % 4 = 1 then 'Customer called: tracking has shown out for delivery for days and the delivery date cannot be changed.'
         else 'Web form: the delivery date cannot be changed; the page says the parcel is already out for delivery.'
       end,
       case when n % 2 = 0 then 'agent' when n % 4 = 1 then 'phone' else 'web' end,
       (:'today'::date - 1 - n % 3) + time '09:00' + ((n * 29) % 660) * interval '1 minute'
from plan
where incident and off > 0 and n % 3 <> 2;

insert into tickets (id, ticket_id, tracking_no, category, description, status, channel, created_at)
select row_number() over w,
       'TCK-' || lpad((row_number() over w)::text, 6, '0'),
       tracking_no, category, description,
       case when created_at < :'today'::date - 4 then 'CLOSED' else 'OPEN' end,
       channel, created_at
from tk
window w as (order by created_at, n);
