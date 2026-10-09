#!/bin/sh
# Applies the seed of $KERVAN_ENV (SPEC §5.1, §10). Runs in the compose service
# `seed` once core is healthy, i.e. once Flyway has migrated the schema.
#
#   roles.sql        the read-only login role kervan_reader (every environment)
#   $KERVAN_ENV.sql  the data; dev and staging are reset to their fixtures on
#                    every run, prod_sim is seeded only into an empty database
set -eu

env="${KERVAN_ENV:?KERVAN_ENV is not set}"
case "$env" in
  dev | staging | prod_sim) ;;
  *) echo "seed: unknown KERVAN_ENV '$env' (dev, staging or prod_sim)" >&2; exit 2 ;;
esac

psql() { command psql -X -q -v ON_ERROR_STOP=1 "$@"; }

if [ "$(psql -tAc "select to_regclass('public.flyway_schema_history') is not null")" != "t" ]; then
  echo "seed: core's migrations have not run (no flyway_schema_history)" >&2
  exit 1
fi

psql --output=/dev/null -f /seed/roles.sql

if [ "$env" = prod_sim ] && [ "$(psql -tAc 'select count(*) from shipments')" != "0" ]; then
  echo "seed: prod_sim already holds data; leaving it as it is"
else
  psql --output=/dev/null --single-transaction -f "/seed/$env.sql"
fi

psql -tAc "select format('seed %s: %s customers, %s shipments, %s deliveries, %s events, %s tickets',
                         '$env',
                         (select count(*) from customers), (select count(*) from shipments),
                         (select count(*) from deliveries), (select count(*) from shipment_events),
                         (select count(*) from tickets))"
