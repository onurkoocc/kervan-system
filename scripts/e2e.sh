#!/usr/bin/env bash
# The end-to-end check of test.integration: staging plus the integration
# overlay (internal network: no egress, nothing published) under a fresh
# compose project, then the scenarios in e2e/scenarios, then teardown.
#
#   scripts/e2e.sh [extra overlay file]...
#
# Exit code: the scenario runner's (0 every check passed, 1 a check failed,
# 2 invalid scenarios), or 3 when the environment did not come up.
#
# KERVAN_SRC  directory of the kervan-* working copies to build (default: the
#             siblings of kervan-system). For other copies KERVAN_TAG defaults
#             to a tag derived from that path, so the images of the main
#             copies are not overwritten.
# E2E_KEEP=1  leave the environment running for inspection.
# Extra overlays (paths) are applied after integration.yml, e.g. to inject a fault.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

if [ -n "${KERVAN_SRC:-}" ]; then
  KERVAN_SRC=$(abspath "$KERVAN_SRC")
  export KERVAN_SRC
  if [ -z "${KERVAN_TAG:-}" ]; then
    KERVAN_TAG="src-$(printf '%s' "$KERVAN_SRC" | sha256sum | cut -c1-12)"
    export KERVAN_TAG
  fi
fi

project="kervan-e2e-$(date +%Y%m%d%H%M%S)-$$"
files+=(-f "$COMPOSE_DIR/staging.yml" -f "$COMPOSE_DIR/integration.yml")
for overlay in "$@"; do
  [ -f "$overlay" ] || die "no such overlay: $overlay"
  files+=(-f "$(abspath "$(dirname "$overlay")")/$(basename "$overlay")")
done

# shellcheck disable=SC2317,SC2329 # invoked by the EXIT trap
teardown() {
  if [ "${E2E_KEEP:-}" = 1 ]; then
    echo "e2e: left running as compose project $project" >&2
  else
    compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap teardown EXIT

report="$KERVAN_DATA/e2e/$project.json"
mkdir -p "$(dirname "$report")"

echo "e2e: project $project"
echo "e2e: sources ${KERVAN_SRC:-$(abspath "$KERVAN_SYSTEM/..")}, image tag ${KERVAN_TAG:-local}"
started=$SECONDS

compose build --quiet
echo "e2e: images built in $((SECONDS - started)) s"

if ! compose up -d "${SERVICES[@]}" seed || ! wait_seed || ! wait_healthy "${SERVICES[@]}"; then
  echo "e2e: FAILED: staging did not come up" >&2
  exit 3
fi
up=$SECONDS
echo "e2e: staging up and seeded in $((up - started)) s"

set +e
compose run --rm --no-deps -T e2e >"$report"
rc=$?
set -e

# One line per scenario; for a failed run, the checks that failed.
awk '/^      "id": /     { id = $2; gsub(/[",]/, "", id) }
     /^      "passed": / { print ($2 ~ /true/ ? "  PASS " : "  FAIL ") id }' "$report"
if [ $rc -ne 0 ]; then
  echo "e2e: failed checks (first 12 lines):"
  grep -A1 -B1 '^          "passed": false' "$report" | grep -E '"(name|detail)"' | sed 's/^ */    /' | head -n 12 || true
  echo "e2e: latest warnings and errors of the services:"
  for service in voice mcp auth core search; do
    compose logs --no-log-prefix "$service" 2>/dev/null | grep -E '"level":"(warn|error)"' | tail -n 3 | sed 's/^/    /' || true
  done
fi
echo "e2e: report $report"

if [ $rc -eq 0 ]; then
  echo "e2e: PASSED (scenarios $((SECONDS - up)) s, total $((SECONDS - started)) s)"
else
  echo "e2e: FAILED, exit code $rc (total $((SECONDS - started)) s)"
fi
exit $rc
