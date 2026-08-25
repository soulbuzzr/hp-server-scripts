#!/usr/bin/env bash
set -euo pipefail

# --- pull secrets/config from the systemd EnvironmentFile ---
# PROXY_BOT_TOKEN, CHAT_ID, IMMICH_HOST, IMMICH_API_KEY expected in immich_bots.env

source /home/hpserver/System_Scripts/Immich/env/immich_bots.env

send_tg() {
    curl -fsS "https://api.telegram.org/bot${PROXY_BOT_TOKEN}/sendMessage" \
         -d chat_id="${CHAT_ID}" \
         --data-urlencode text="$1" \
         >/dev/null
}

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
    send_tg "⚠ Immich tunnel restarted but no URL found in logs — config NOT updated"
    exit 1
fi

# 2. Wait for the immich_server container to report healthy
#    (on boot, docker.service and the tunnel come up long before the app does)
ready_deadline=$((SECONDS + 180))
immich_up=false
while (( SECONDS < ready_deadline )); do
    status=$(docker inspect --format='{{.State.Health.Status}}' immich_server 2>/dev/null || echo "missing")
    if [[ "$status" == "healthy" ]]; then
        immich_up=true
        break
    fi
    sleep 5
done

if ! $immich_up; then
    send_tg "⚠ New tunnel URL ${url} but immich_server never became healthy — config NOT updated"
    exit 1
fi

# 3. Push the new URL into Immich's externalDomain via the API
#    (GET full config, patch just externalDomain, PUT the whole thing back —
#    Immich's PUT replaces the entire config, so a partial body would nuke everything else)
tmp_config=$(mktemp)
trap 'rm -f "$tmp_config"' EXIT

if ! curl -fsS "${IMMICH_HOST}/api/system-config" \
        -H "Accept: application/json" \
        -H "x-api-key: ${IMMICH_API_KEY}" > "$tmp_config"; then
    send_tg "⚠ New tunnel URL ${url} but failed to GET Immich config"
    exit 1
fi

updated_config=$(jq --arg d "$url" '.server.externalDomain = $d' "$tmp_config")

if ! curl -fsS -X PUT "${IMMICH_HOST}/api/system-config" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${IMMICH_API_KEY}" \
        -d "$updated_config" > /dev/null; then
    send_tg "⚠ New tunnel URL ${url} but PUT to Immich config failed"
    exit 1
fi

# 4. Success notification
send_tg "🔗 Immich tunnel rotated + config updated: ${url}"