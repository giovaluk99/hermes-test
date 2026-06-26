#!/usr/bin/env bash
# pull-logs.sh — mirror every Agent37 instance's logs into ./logs/<id>/.
#
# There is no logs endpoint. This stitches the three sources the platform exposes:
#   1. runtime log files in the instance  -> GET /v1/files/content (no size cap)
#   2. which files exist                   -> POST /v1/instances/{id}/exec (find)
#   3. agent conversation history          -> GET /v1/sessions  (Agent API)
#
# Run on a schedule (cron/launchd) for continuous pulling. Each run overwrites the
# local copy with the instance's current full file — idempotent, always-latest mirror.
#
# Config (env): AGENT37_KEY (required), AGENT37_API, AGENT37_APP_DOMAIN,
#   AGENT37_LOG_DIR (default ./logs), AGENT37_LOG_SRC (dir inside instance).
#
# ponytail: re-pulls each whole file every run. Fine for small logs; if they grow
# large, switch to incremental tail by byte offset (exec 'tail -c +$N file').
set -euo pipefail

API="${AGENT37_API:-https://api.agent37.com/v1}"
KEY="${AGENT37_KEY:-${AGENT37_GIO_TEST:-}}"
APP="${AGENT37_APP_DOMAIN:-agent37.app}"
OUT="${AGENT37_LOG_DIR:-./logs}"
SRC="${AGENT37_LOG_SRC:-/home/node/.hermes/logs}"   # OpenClaw uses a different path

[ -n "$KEY" ] || { echo "set AGENT37_KEY (or AGENT37_GIO_TEST)" >&2; exit 2; }
auth=(-H "Authorization: Bearer $KEY")

ids=$(curl -sS "${auth[@]}" "$API/instances" | jq -r '.data[].id')
[ -n "$ids" ] || { echo "no instances in workspace"; exit 0; }

stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for id in $ids; do
  base="https://$id.$APP"
  dir="$OUT/$id"; mkdir -p "$dir"

  # 1+2. discover log files (one exec), then pull each uncapped via files endpoint
  files=$(jq -nc --arg c "find $SRC -type f 2>/dev/null" '{command:$c}' \
    | curl -sS -X POST "$API/instances/$id/exec" "${auth[@]}" \
        -H "Content-Type: application/json" -d @- | jq -r '.stdout // ""')
  n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    name="${f#"$SRC"/}"; name="${name//\//_}"          # flatten subdirs
    curl -fsS -G "$base/v1/files/content" --data-urlencode "path=$f" \
      "${auth[@]}" -o "$dir/$name" && n=$((n+1)) || echo "  ! failed $f"
  done <<< "$files"

  # 3. conversation history (sessions + their responses)
  curl -fsS "$base/v1/sessions" "${auth[@]}" -o "$dir/_sessions.json" 2>/dev/null || true

  echo "[$stamp] $id: pulled $n log file(s) + sessions -> $dir"
done
