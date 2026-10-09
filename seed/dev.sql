-- dev: a small hand-written data set for a developer's own environment.
-- Applied by seed/apply.sh in one transaction after core's migrations; every
-- run resets the tables to exactly this. Dates are relative to today in
-- Europe/Istanbul, core's clock zone. All data is synthetic; phone numbers use
-- the unassigned +90 500 prefix and e-mails the reserved .test domain.
--
-- Try (verification code = last four digits of the phone):
--   KRV20000001  in transit, İstanbul → Ankara, delivery today+2, code 1234
--   KRV20000002  in transit, İzmir → Bursa, delivery today+4, code 5678
--   KRV20000003  out for delivery today (cannot be rescheduled)
--   KRV20000004  delivered yesterday
--   KRV20000005  created, not picked up yet, delivery today+6, code 2468
--   KRV20000006  returned to sender

set time zone 'Europe/Istanbul';
select current_date as today \gset

truncate tickets, shipment_events, deliveries, shipments, customers restart identity cascade;
alter sequence ticket_number_seq restart;

insert into customers (id, full_name, phone, email, city) values
  (1, 'Deniz Akın',    '+90 500 100 12 34', 'deniz.akin@example.test',    'Ankara'),
  (2, 'Selin Karaca',  '+90 500 100 56 78', 'selin.karaca@example.test',  'Bursa'),
  (3, 'Emre Yalçın',   '+90 500 100 90 12', 'emre.yalcin@example.test',   'İstanbul'),
  (4, 'Ece Tunalı',    '+90 500 100 33 44', 'ece.tunali@example.test',    'İzmir'),
  (5, 'Kerem Sarıkaya','+90 500 100 24 68', 'kerem.sarikaya@example.test','Antalya'),
  (6, 'Merve Ilgaz',   '+90 500 100 77 01', 'merve.ilgaz@example.test',   'Konya');
select setval(pg_get_serial_sequence('customers', 'id'), (select max(id) from customers));

insert into shipments (tracking_no, customer_id, status, origin_city, destination_city, created_at) values
  ('KRV20000001', 1, 'IN_TRANSIT',       'İstanbul', 'Ankara',   :'today'::date - 2 + time '10:15'),
  ('KRV20000002', 2, 'IN_TRANSIT',       'İzmir',    'Bursa',    :'today'::date - 1 + time '14:40'),
  ('KRV20000003', 3, 'OUT_FOR_DELIVERY', 'Ankara',   'İstanbul', :'today'::date - 3 + time '09:05'),
  ('KRV20000004', 4, 'DELIVERED',        'Bursa',    'İzmir',    :'today'::date - 5 + time '16:20'),
  ('KRV20000005', 5, 'CREATED',          'Konya',    'Antalya',  :'today'::date - 1 + time '18:30'),
  ('KRV20000006', 6, 'RETURNED',         'Adana',    'Konya',    :'today'::date - 12 + time '11:00');

insert into deliveries (id, tracking_no, delivery_date, "window", status, attempts) values
  (1, 'KRV20000001', :'today'::date + 2,  'MORNING',   'SCHEDULED', 0),
  (2, 'KRV20000002', :'today'::date + 4,  'AFTERNOON', 'SCHEDULED', 0),
  (3, 'KRV20000003', :'today'::date,      'EVENING',   'SCHEDULED', 0),
  (4, 'KRV20000004', :'today'::date - 1,  'MORNING',   'DELIVERED', 1),
  (5, 'KRV20000005', :'today'::date + 6,  'AFTERNOON', 'SCHEDULED', 0),
  (6, 'KRV20000006', :'today'::date - 7,  'MORNING',   'FAILED',    3);
select setval(pg_get_serial_sequence('deliveries', 'id'), (select max(id) from deliveries));

-- Every event lies in the past, so a new event core appends is always the latest.
insert into shipment_events (id, tracking_no, at, description) values
  (1,  'KRV20000001', :'today'::date - 2 + time '10:15', 'Shipment created'),
  (2,  'KRV20000001', :'today'::date - 2 + time '17:40', 'Picked up in İstanbul'),
  (3,  'KRV20000001', :'today'::date - 1 + time '06:55', 'Departed İstanbul transfer centre'),
  (4,  'KRV20000002', :'today'::date - 1 + time '14:40', 'Shipment created'),
  (5,  'KRV20000002', :'today'::date - 1 + time '19:10', 'Picked up in İzmir'),
  (6,  'KRV20000003', :'today'::date - 3 + time '09:05', 'Shipment created'),
  (7,  'KRV20000003', :'today'::date - 2 + time '08:30', 'Arrived at İstanbul transfer centre'),
  (8,  'KRV20000003', now() - interval '2 hours',        'Out for delivery'),
  (9,  'KRV20000004', :'today'::date - 5 + time '16:20', 'Shipment created'),
  (10, 'KRV20000004', :'today'::date - 2 + time '07:45', 'Arrived at İzmir transfer centre'),
  (11, 'KRV20000004', :'today'::date - 1 + time '08:10', 'Out for delivery'),
  (12, 'KRV20000004', :'today'::date - 1 + time '11:32', 'Delivered'),
  (13, 'KRV20000005', :'today'::date - 1 + time '18:30', 'Shipment created'),
  (14, 'KRV20000006', :'today'::date - 12 + time '11:00', 'Shipment created'),
  (15, 'KRV20000006', :'today'::date - 7 + time '18:05', 'Delivery attempt failed: recipient not at home'),
  (16, 'KRV20000006', :'today'::date - 4 + time '09:20', 'Returned to sender');

insert into tickets (id, ticket_id, tracking_no, category, description, status, channel, created_at) values
  (1, 'TCK-000001', 'KRV20000004', 'DAMAGED', 'Customer reports a dented box; contents intact.', 'CLOSED', 'web', :'today'::date - 1 + time '15:02'),
  (2, 'TCK-000002', null,          'OTHER',   'Question about opening hours on public holidays.', 'OPEN', 'phone', :'today'::date - 1 + time '10:47');
