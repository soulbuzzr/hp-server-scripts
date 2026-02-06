#!/bin/bash
set -u
set -o pipefail

# Shared library for System_Health_Monitor scripts.
# - Loads env from:   $BASE_DIR/env/system_health_bot.env
# - Loads config from:$BASE_DIR/conf/system_limits.conf
# - Provides: log, tg_send, internet_up

# ================= BASE DIRECTORY =================
_health_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SYSTEM_HEALTH_BASE_DIR:-$(cd "$_health_lib_dir/.." && pwd)}"

ENV_FILE="${SYSTEM_HEALTH_ENV_FILE:-$BASE_DIR/env/system_health_bot.env}"
CONF_FILE="${SYSTEM_HEALTH_CONF_FILE:-$BASE_DIR/conf/system_limits.conf}"

# ================= LOAD ENV =================
if [ ! -r "$ENV_FILE" ]; then
  echo "ERROR: Missing env file: $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

: "${TG_BOT_TOKEN:?Missing TG_BOT_TOKEN}"
: "${TG_CHAT_ID:?Missing TG_CHAT_ID}"

# ================= LOAD CONFIG =================
if [ ! -r "$CONF_FILE" ]; then
  echo "ERROR: Missing config file: $CONF_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONF_FILE"

# ================= LOGGING =================
LOG_DIR="${SYSTEM_HEALTH_LOG_DIR:-/var/log/system_health}"
LOG_FILE="${SYSTEM_HEALTH_LOG_FILE:-$LOG_DIR/health.log}"

mkdir -p "$LOG_DIR"

log() {
  # Usage: log COMPONENT MESSAGE...
  # Example: log CPU "avg=${CPU_AVG}%"
  local component="${1:-MAIN}"
  shift || true
  echo "$(date '+%F %T') [$component] $*" >> "$LOG_FILE"
}

# ================= TELEGRAM =================
tg_send() {
  # Usage: tg_send "message"
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=$1" \
    --data-urlencode "parse_mode=Markdown" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null
}

# ================= CONNECTIVITY =================
internet_up() {
  ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
}

