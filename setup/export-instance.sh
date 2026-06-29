#!/usr/bin/env bash
# export-instance.sh — snapshot the persistent sandbox state into ./exports/ (git-ignored).
#
# What you CAN and CANNOT capture:
#   • Base OS layer  = Agent37's image `image_ref` (e.g. ghcr.io/agent37-platform/hermes:…).
#       Proprietary + ephemeral (rebuilt on update). You can't pull/tar it — but the
#       ref is recorded (base-image.json); Agent37 rebuilds the box from it.
#   • Persistent disk = EVERYTHING under /home/node (6 GB, 9p). THIS is your real
#       "image": ~/.hermes (config, skills, memories, sessions, state.db, cron, .env),
#       ~/.claude, ~/.agent37 (patches+hooks), ~/workspace, the KB, brew installs.
#   ⇒ base-image.json + this snapshot = full reconstruction.
#
# Requires the instance RUNNING (exec + Files API). A stopped/past_due instance must
# be funded first: top up at dashboard/cloud/billing, then `POST /instances/{id}/start`.
#
# ⚠ The tar + hermes backup contain SECRETS (OAuth token, provider keys, creds).
#   Output goes to ./exports/ which is git-ignored. NEVER commit it.
set -euo pipefail
API="${AGENT37_API:-https://api.agent37.com/v1}"
KEY="${AGENT37_KEY:-${AGENT37_GIO_TEST:-}}"
APP="${AGENT37_APP_DOMAIN:-agent37.app}"
INST="${AGENT37_INSTANCE:-ym8dpjcfhi}"
OUT="${1:-exports/$INST-$(date -u +%Y%m%d-%H%M%S)}"
[ -n "$KEY" ] || { echo "set AGENT37_KEY (or AGENT37_GIO_TEST)" >&2; exit 2; }
auth=(-H "Authorization: Bearer $KEY")
base="https://$INST.$APP"

exec_i(){ jq -nc --arg c "$1" '{command:$c}' \
  | curl -sS -X POST "$API/instances/$INST/exec" "${auth[@]}" -H "Content-Type: application/json" -d @- \
  | jq -r '.stdout // ""'; }
pull(){ curl -fsS -G "$base/v1/files/content" --data-urlencode "path=$1" "${auth[@]}" -o "$2"; }

st=$(curl -sS "$API/instances/$INST" "${auth[@]}" | jq -r .status)
[ "$st" = "running" ] || { echo "instance is '$st' — start it first (needs wallet balance):"; \
  echo "  curl -X POST $API/instances/$INST/start -H \"Authorization: Bearer \$AGENT37_KEY\""; exit 1; }
mkdir -p "$OUT"

echo "→ 1/4 file manifest + dir tree (see the structure)"
exec_i 'cd /home/node && find . -type f -printf "%10s  %p\n" 2>/dev/null | sort -k2' > "$OUT/manifest.txt"
exec_i 'cd /home/node && find . -maxdepth 4 -type d 2>/dev/null | sort'           > "$OUT/tree-dirs.txt"

echo "→ 2/4 restorable Hermes backup (config, skills, memories, sessions, state.db, cron, .env)"
exec_i 'mkdir -p /home/node/exports && (hermes backup --output /home/node/exports/hermes-backup.zip 2>&1 || hermes backup 2>&1) | tail -3' || true
bz=$(exec_i 'ls -1t /home/node/exports/*.zip $HOME/.hermes/backups/*.zip 2>/dev/null | head -1')
[ -n "$bz" ] && pull "$bz" "$OUT/hermes-backup.zip" && echo "   + hermes-backup.zip ($(wc -c <"$OUT/hermes-backup.zip") bytes)"

echo "→ 3/4 full /home/node tarball (the complete persistent snapshot)"
exec_i 'cd /home/node && tar czf /tmp/home-node.tar.gz --exclude=exports --exclude="**/__pycache__" --exclude="**/.cache" --exclude="**/node_modules" 2>/dev/null . ; echo packed' >/dev/null
pull /tmp/home-node.tar.gz "$OUT/home-node.tar.gz" && echo "   + home-node.tar.gz ($(wc -c <"$OUT/home-node.tar.gz") bytes)"

echo "→ 4/4 base image ref (the OS layer Agent37 rebuilds from)"
curl -sS "$API/instances/$INST" "${auth[@]}" | jq '{image_ref, resources, template, status}' > "$OUT/base-image.json"

echo "✓ exported -> $OUT"
echo "  restore Hermes state on a fresh instance with:  hermes import <hermes-backup.zip>"
echo "  or unpack the full disk:                        tar xzf home-node.tar.gz -C /home/node"
