-- staging: the fixed data the scenarios assume. Applied by seed/apply.sh in one
-- transaction after core's migrations; every run resets the tables to exactly
-- this. All data is synthetic.
--
-- KRV10000001–KRV10000008 match the table in
-- kervan-voice-evals/scenarios/README.md exactly; KRV99999999 must not exist.
-- KRV10000101–KRV10000104 belong to the end-to-end scenarios in ../e2e, so the
-- two suites never touch each other's parcels.
--
-- Dates are relative to today in Europe/Istanbul, core's clock zone; the
-- scenarios' {{today+N}} templates expand against the same date. Every event
-- lies in the past, so an event core appends is always a shipment's latest.

set time zone 'Europe/Istanbul';
select current_date as today \gset

truncate tickets, shipment_events, deliveries, shipments, customers restart identity cascade;
alter sequence ticket_number_seq restart;

-- Phone numbers use the unassigned +90 500 prefix; the last four digits are the
-- verification codes the scenarios use.
insert into customers (id, full_name, phone, email, city) values
  (1,  'Aylin Test',   '+90 500 000 11 01', 'aylin.test@example.test',   'Ankara'),
  (2,  'Baran Test',   '+90 500 000 48 21', 'baran.test@example.test',   'İstanbul'),
  (3,  'Cemre Test',   '+90 500 000 73 10', 'cemre.test@example.test',   'Bursa'),
  (4,  'Doruk Test',   '+90 500 000 50 66', 'doruk.test@example.test',   'İzmir'),
  (5,  'Ekin Test',    '+90 500 000 55 05', 'ekin.test@example.test',    'Konya'),
  (6,  'Feyza Test',   '+90 500 000 66 06', 'feyza.test@example.test',   'İstanbul'),
  (7,  'Gökay Test',   '+90 500 000 22 90', 'gokay.test@example.test',   'Ankara'),
  (8,  'Hazal Test',   '+90 500 000 61 42', 'hazal.test@example.test',   'İzmir'),
  (101, 'Irmak E2e',   '+90 500 001 01 01', 'irmak.e2e@example.test',    'Ankara'),
  (102, 'Kaan E2e',    '+90 500 001 33 07', 'kaan.e2e@example.test',     'İzmir'),
  (103, 'Lale E2e',    '+90 500 001 03 03', 'lale.e2e@example.test',     'Bursa'),
  (104, 'Mert E2e',    '+90 500 001 90 54', 'mert.e2e@example.test',     'Ankara');
select setval(pg_get_serial_sequence('customers', 'id'), (select max(id) from customers));

insert into shipments (tracking_no, customer_id, status, origin_city, destination_city, created_at) values
  -- kervan-voice-evals
  ('KRV10000001', 1,   'IN_TRANSIT',       'İstanbul',  'Ankara',   :'today'::date - 2 + time '10:00'),
  ('KRV10000002', 2,   'IN_TRANSIT',       'İzmir',     'İstanbul', :'today'::date - 1 + time '11:00'),
  ('KRV10000003', 3,   'IN_TRANSIT',       'Ankara',    'Bursa',    :'today'::date - 2 + time '12:00'),
  ('KRV10000004', 4,   'DELIVERED',        'Antalya',   'İzmir',    :'today'::date - 5 + time '09:30'),
  ('KRV10000005', 5,   'DELIVERED',        'Bursa',     'Konya',    :'today'::date - 4 + time '13:15'),
  ('KRV10000006', 6,   'IN_TRANSIT',       'Gaziantep', 'İstanbul', :'today'::date - 9 + time '15:45'),
  ('KRV10000007', 7,   'IN_TRANSIT',       'Kayseri',   'Ankara',   :'today'::date - 1 + time '16:20'),
  ('KRV10000008', 8,   'IN_TRANSIT',       'Eskişehir', 'İzmir',    :'today'::date - 1 + time '08:50'),
  -- end-to-end scenarios (../e2e)
  ('KRV10000101', 101, 'IN_TRANSIT',       'İstanbul',  'Ankara',   :'today'::date - 1 + time '10:30'),
  ('KRV10000102', 102, 'IN_TRANSIT',       'Ankara',    'İzmir',    :'today'::date - 1 + time '12:10'),
  ('KRV10000103', 103, 'DELIVERED',        'İzmir',     'Bursa',    :'today'::date - 4 + time '09:00'),
  ('KRV10000104', 104, 'OUT_FOR_DELIVERY', 'Konya',     'Ankara',   :'today'::date - 3 + time '14:00');

insert into deliveries (id, tracking_no, delivery_date, "window", status, attempts) values
  (1,   'KRV10000001', :'today'::date + 2, 'MORNING',   'SCHEDULED', 0),
  (2,   'KRV10000002', :'today'::date + 5, 'AFTERNOON', 'SCHEDULED', 0),
  (3,   'KRV10000003', :'today'::date + 2, 'EVENING',   'SCHEDULED', 0),
  (4,   'KRV10000004', :'today'::date - 2, 'MORNING',   'DELIVERED', 1),
  (5,   'KRV10000005', :'today'::date - 1, 'AFTERNOON', 'DELIVERED', 1),
  (6,   'KRV10000006', :'today'::date - 5, 'MORNING',   'SCHEDULED', 0),
  (7,   'KRV10000007', :'today'::date + 3, 'AFTERNOON', 'SCHEDULED', 0),
  (8,   'KRV10000008', :'today'::date + 4, 'EVENING',   'SCHEDULED', 0),
  (101, 'KRV10000101', :'today'::date + 3, 'MORNING',   'SCHEDULED', 0),
  (102, 'KRV10000102', :'today'::date + 6, 'AFTERNOON', 'SCHEDULED', 0),
  (103, 'KRV10000103', :'today'::date - 1, 'MORNING',   'DELIVERED', 1),
  (104, 'KRV10000104', :'today'::date,     'AFTERNOON', 'SCHEDULED', 0);
select setval(pg_get_serial_sequence('deliveries', 'id'), (select max(id) from deliveries));

insert into shipment_events (id, tracking_no, at, description) values
  (1,  'KRV10000001', :'today'::date - 2 + time '10:00', 'Shipment created'),
  (2,  'KRV10000001', :'today'::date - 2 + time '18:20', 'Picked up in İstanbul'),
  (3,  'KRV10000001', :'today'::date - 1 + time '07:05', 'Departed İstanbul transfer centre'),
  (4,  'KRV10000002', :'today'::date - 1 + time '11:00', 'Shipment created'),
  (5,  'KRV10000002', :'today'::date - 1 + time '17:30', 'Picked up in İzmir'),
  (6,  'KRV10000003', :'today'::date - 2 + time '12:00', 'Shipment created'),
  (7,  'KRV10000003', :'today'::date - 1 + time '09:40', 'Departed Ankara transfer centre'),
  (8,  'KRV10000004', :'today'::date - 5 + time '09:30', 'Shipment created'),
  (9,  'KRV10000004', :'today'::date - 2 + time '08:15', 'Out for delivery'),
  (10, 'KRV10000004', :'today'::date - 2 + time '10:52', 'Delivered'),
  (11, 'KRV10000005', :'today'::date - 4 + time '13:15', 'Shipment created'),
  (12, 'KRV10000005', :'today'::date - 1 + time '12:05', 'Out for delivery'),
  (13, 'KRV10000005', :'today'::date - 1 + time '15:37', 'Delivered'),
  (14, 'KRV10000006', :'today'::date - 9 + time '15:45', 'Shipment created'),
  (15, 'KRV10000006', :'today'::date - 8 + time '19:00', 'Departed Gaziantep transfer centre'),
  (16, 'KRV10000007', :'today'::date - 1 + time '16:20', 'Shipment created'),
  (17, 'KRV10000008', :'today'::date - 1 + time '08:50', 'Shipment created'),
  (18, 'KRV10000008', :'today'::date - 1 + time '17:10', 'Picked up in Eskişehir'),
  (101, 'KRV10000101', :'today'::date - 1 + time '10:30', 'Shipment created'),
  (102, 'KRV10000101', :'today'::date - 1 + time '19:45', 'Departed İstanbul transfer centre'),
  (103, 'KRV10000102', :'today'::date - 1 + time '12:10', 'Shipment created'),
  (104, 'KRV10000103', :'today'::date - 4 + time '09:00', 'Shipment created'),
  (105, 'KRV10000103', :'today'::date - 1 + time '08:40', 'Out for delivery'),
  (106, 'KRV10000103', :'today'::date - 1 + time '13:25', 'Delivered'),
  (107, 'KRV10000104', :'today'::date - 3 + time '14:00', 'Shipment created'),
  (108, 'KRV10000104', :'today'::date - 1 + time '21:10', 'Arrived at Ankara transfer centre'),
  (109, 'KRV10000104', now() - interval '90 minutes',    'Out for delivery');
