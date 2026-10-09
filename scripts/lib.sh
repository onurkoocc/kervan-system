# shellcheck shell=bash disable=SC2034
# Shared by up.sh, down.sh and e2e.sh. Source it, then set `project` and add
# overlays to `files` before calling `compose`. (SC2034: the variables here are
# used by the scripts that source this file, and `project` set there is used here.)

# abspath DIR: absolute path; on Git Bash in the C:/... form docker.exe understands.
abspath() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

KERVAN_SYSTEM=$(abspath "$(dirname "${BASH_SOURCE[0]}")/..")
COMPOSE_DIR="$KERVAN_SYSTEM/compose"
# Git Bash on Windows would rewrite container paths such as /seed; keep them as they are.
export MSYS_NO_PATHCONV=1
export KERVAN_DATA="${KERVAN_DATA:-$KERVAN_SYSTEM/data}"

# The long-running services; logs-init and seed are one-shot.
SERVICES=(postgres core auth search mcp voice)

project=""
files=(-f "$COMPOSE_DIR/base.yml")

die() {
  echo "$(basename "$0"): $*" >&2
  exit 2
}

check_env() {
  case "${1:-}" in
    dev | staging | prod_sim) ;;
    *) die "usage: $(basename "$0") dev|staging|prod_sim" ;;
  esac
}

compose() {
  docker compose -p "$project" "${files[@]}" "$@"
}

# wait_healthy <service>...: until each reports healthy (KERVAN_WAIT_SECONDS, default 300).
wait_healthy() {
  local deadline=$((SECONDS + ${KERVAN_WAIT_SECONDS:-300}))
  local service id status
  for service in "$@"; do
    while :; do
      id=$(compose ps -q "$service")
      status=missing
      [ -n "$id" ] && status=$(docker inspect -f '{{.State.Health.Status}}' "$id" 2>/dev/null || echo missing)
      [ "$status" = healthy ] && break
      if [ $SECONDS -ge $deadline ] || [ "$status" = unhealthy ]; then
        echo "$service is $status" >&2
        compose logs --tail 50 "$service" >&2 || true
        return 1
      fi
      sleep 2
    done
  done
}

# wait_seed: until the one-shot seed service has exited; fails unless it exited 0.
wait_seed() {
  local id code
  id=$(compose ps -a -q seed)
  [ -n "$id" ] || { echo "no seed container" >&2; return 1; }
  code=$(docker wait "$id")
  if [ "$code" != 0 ]; then
    compose logs seed >&2 || true
    echo "the seed failed (exit $code)" >&2
    return 1
  fi
}
