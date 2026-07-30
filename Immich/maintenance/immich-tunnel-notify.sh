#!/usr/bin/env bash
set -euo pipefail

# --- pull secrets/config from the systemd EnvironmentFile ---
# PROXY_BOT_TOKEN, CHAT_ID, IMMICH_HOST, IMMICH_API_KEY expected in immich_bots.env

source /home/hpserver/System_Scripts/Immich/env/immich_bots.env

# 1. Extract the fresh tunnel URL from the just-restarted service's logs
deadline=$((SECONDS + 90))
url=""
while (( SECONDS < deadline )); do
    url=$(journalctl -u immich-tunnel.service --since "-2 min" --no-pager -o cat \
          | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1) || true
    [[ -n "$url" ]] && break
    sleep 2
done

if [[ -z "$url" ]]; then
    curl -fsS "https://api.telegram.org/bot${PROXY_BOT_TOKEN}/sendMessage" \
         -d chat_id="${CHAT_ID}" \
         --data-urlencode text="⚠️ Immich tunnel restarted but no URL found in logs — config NOT updated" \
         >/dev/null
    exit 1
fi

# 2. Push the new URL into Immich's externalDomain via the API
#    (GET full config, patch just externalDomain, PUT the whole thing back —
#    Immich's PUT replaces the entire config, so a partial body would nuke everything else)
tmp_config=$(mktemp)
trap 'rm -f "$tmp_config"' EXIT

if ! curl -fsS "${IMMICH_HOST}/api/system-config" \
        -H "Accept: application/json" \
        -H "x-api-key: ${IMMICH_API_KEY}" > "$tmp_config"; then
    curl -fsS "https://api.telegram.org/bot${PROXY_BOT_TOKEN}/sendMessage" \
         -d chat_id="${CHAT_ID}" \
         --data-urlencode text="⚠️ New tunnel URL ${url} but failed to GET Immich config" \
         >/dev/null
    exit 1
fi

updated_config=$(jq --arg d "$url" '.server.externalDomain = $d' "$tmp_config")

if ! curl -fsS -X PUT "${IMMICH_HOST}/api/system-config" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${IMMICH_API_KEY}" \
        -d "$updated_config" > /dev/null; then
    curl -fsS "https://api.telegram.org/bot${PROXY_BOT_TOKEN}/sendMessage" \
         -d chat_id="${CHAT_ID}" \
         --data-urlencode text="⚠️ New tunnel URL ${url} but PUT to Immich config failed" \
         >/dev/null
    exit 1
fi

# 3. Success notification
curl -fsS "https://api.telegram.org/bot${PROXY_BOT_TOKEN}/sendMessage" \
     -d chat_id="${CHAT_ID}" \
     --data-urlencode text="🔗 Immich tunnel rotated + config updated: ${url}" \
     >/dev/null