#!/usr/bin/env bash
set -euo pipefail

# --- Config: pulled from EnvironmentFile ---
# IMMICH_HOST, IMMICH_API_KEY, BOT_TOKEN, CHAT_ID expected in env

source /home/hpserver/System_Scripts/Immich/env/tunnel.env

STATE_FILE="/home/hpserver/System_Scripts/Immich/maintenance/.immich_last_notified_version"
GITHUB_REPO="immich-app/immich"

send_telegram() {
    local text="$1"
    curl -fsS "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
         -d chat_id="${CHAT_ID}" \
         -d parse_mode="HTML" \
         --data-urlencode text="${text}" \
         >/dev/null
}

# 1. Get currently running Immich version
current_json=$(curl -fsS -H "x-api-key: ${IMMICH_API_KEY}" \
                    "${IMMICH_HOST}/api/server/version") || {
    send_telegram "⚠️ Immich update check: failed to reach local server API"
    exit 1
}
current_version=$(echo "$current_json" | jq -r '"\(.major).\(.minor).\(.patch)"')

# 2. Get latest release from GitHub
release_json=$(curl -fsS -H "Accept: application/vnd.github+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/releases/latest") || {
    send_telegram "⚠️ Immich update check: failed to reach GitHub releases API"
    exit 1
}

latest_tag=$(echo "$release_json" | jq -r '.tag_name')
latest_version="${latest_tag#v}"
release_url=$(echo "$release_json" | jq -r '.html_url')
release_body=$(echo "$release_json" | jq -r '.body')

# 3. Compare versions (semver-aware, not just string compare)
if [[ "$current_version" == "$latest_version" ]]; then
    exit 0   # up to date, nothing to do
fi

newer=$(printf '%s\n%s\n' "$current_version" "$latest_version" | sort -V | tail -1)
if [[ "$newer" != "$latest_version" ]]; then
    exit 0   # current is somehow ahead (e.g. running a dev/rc build) — don't alert
fi

# 4. Avoid re-notifying for the same version on every daily run
if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "$latest_version" ]]; then
    exit 0   # already notified about this version
fi

# 5. Build Telegram message (Telegram hard cap is 4096 chars per message)
header="🚀 <b>Immich update available</b>
Current: <code>${current_version}</code>
Latest:  <code>${latest_version}</code>
${release_url}

<b>Release notes:</b>"

# Strip markdown headers/links noise a bit and cap length so header+body fits under 4096
max_body_len=$((3800 - ${#header}))
trimmed_body=$(echo "$release_body" | sed 's/^#\+ //g' | head -c "$max_body_len")

if [[ ${#release_body} -gt ${#trimmed_body} ]]; then
    trimmed_body="${trimmed_body}...
(truncated — see full notes at link above)"
fi

send_telegram "${header}
${trimmed_body}"

# 6. Record that we've notified for this version
echo "$latest_version" > "$STATE_FILE"
