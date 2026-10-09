#!/usr/bin/env bash
# Brings one Kervan environment up and waits until every service is healthy and
# the seed is applied.
#
#   scripts/up.sh dev|staging|prod_sim
#
# Compose project: kervan-<env>. KERVAN_SRC, KERVAN_TAG and KERVAN_DATA are
# passed through to compose (see compose/base.yml and compose/prod_sim.yml).
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

env=${1:-}
check_env "$env"
project="kervan-$env"
files+=(-f "$COMPOSE_DIR/$env.yml")

[ "$env" = prod_sim ] && mkdir -p "$KERVAN_DATA/prod_sim/logs"

started=$SECONDS
compose build --quiet
compose up -d --quiet-pull
wait_seed
wait_healthy "${SERVICES[@]}"

compose logs --no-log-prefix logs-init seed | grep -E '^(seed|logs-init)' | sort -u || true
compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
echo "kervan $env is up ($((SECONDS - started)) s)."
case "$env" in
  dev)
    echo "Try: curl -s localhost:7000/converse -H 'content-type: application/json' \\"
    echo "       -d '{\"conversation_id\":\"c1\",\"utterance\":\"Where is my parcel KRV20000001?\"}'"
    ;;
  prod_sim)
    echo "Read replica: postgresql://kervan_reader:kervan_reader@127.0.0.1:55432/kervan"
    echo "Logs:         $KERVAN_DATA/prod_sim/logs"
    ;;
esac
