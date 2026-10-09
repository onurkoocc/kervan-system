#!/usr/bin/env bash
# Stops one Kervan environment.
#
#   scripts/down.sh dev|staging|prod_sim [--volumes]
#
# --volumes also removes the database and log volumes and, for prod_sim, the
# host log directory $KERVAN_DATA/prod_sim. Images are kept.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

env=${1:-}
check_env "$env"
project="kervan-$env"
files+=(-f "$COMPOSE_DIR/$env.yml")

case "${2:-}" in
  "")
    compose down --remove-orphans
    ;;
  -v | --volumes)
    compose down --volumes --remove-orphans
    if [ "$env" = prod_sim ] && [ -d "$KERVAN_DATA/prod_sim" ]; then
      rm -rf "${KERVAN_DATA:?}/prod_sim"
      echo "removed $KERVAN_DATA/prod_sim"
    fi
    ;;
  *) die "usage: $(basename "$0") dev|staging|prod_sim [--volumes]" ;;
esac
