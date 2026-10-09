#!/bin/sh
# Prepares /var/log/kervan before any service starts (compose service `logs-init`,
# run as root).
#
# - Every Kervan image runs as its own uid, so the shared directory is made
#   world-writable (sticky, like /tmp).
# - If seed/$KERVAN_ENV/logs exists, its pre-baked JSON-lines files are copied
#   in, once. Their timestamps are templates: {{today}} and {{today-N}} expand to
#   dates relative to today in Europe/Istanbul, like the seed's SQL dates, so the
#   logs and the data tell the same story whatever day the environment is built.
set -eu

dir=/var/log/kervan
mkdir -p "$dir"
chmod 1777 "$dir" 2>/dev/null || true # a host bind mount may not allow it; it is then writable already

src="/seed/${KERVAN_ENV:?KERVAN_ENV is not set}/logs"
marker="$dir/.kervan-seed-logs"
[ -d "$src" ] || exit 0
if [ -e "$marker" ]; then
  echo "logs-init: pre-baked logs already in place"
  exit 0
fi

today=$(TZ=Europe/Istanbul date +%F)
script=$(mktemp)
echo "s/{{today}}/$today/g" >"$script"
grep -oh '{{today-[0-9]*}}' "$src"/*.jsonl | sort -u | while read -r token; do
  n=${token#\{\{today-}
  n=${n%\}\}}
  echo "s/{{today-$n}}/$(date -u -d "$today -$n days" +%F)/g" >>"$script"
done

for file in "$src"/*.jsonl; do
  name=$(basename "$file")
  sed -f "$script" "$file" >>"$dir/$name"
  chmod 666 "$dir/$name" 2>/dev/null || true
  echo "logs-init: $name: $(wc -l <"$file") pre-baked lines"
done
rm -f "$script"
date -u +%FT%TZ >"$marker"
