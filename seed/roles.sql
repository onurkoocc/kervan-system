-- The read-only login role of Mandate's read broker (SPEC §5.1): select on
-- v_shipment_overview, tickets and shipment_events, nothing else. Applied in
-- every environment, after core's migrations; safe to run again.

do $$
begin
  if not exists (select from pg_roles where rolname = 'kervan_reader') then
    create role kervan_reader login password 'kervan_reader';
  end if;
end
$$;

alter role kervan_reader with login nosuperuser nocreatedb nocreaterole noreplication password 'kervan_reader';
-- Belt and braces: even a grant made by mistake later cannot write through this role's sessions.
alter role kervan_reader set default_transaction_read_only = on;

revoke all on all tables in schema public from kervan_reader;
revoke all on all sequences in schema public from kervan_reader;
revoke create on schema public from public;

grant connect on database kervan to kervan_reader;
grant usage on schema public to kervan_reader;
grant select on v_shipment_overview, tickets, shipment_events to kervan_reader;
