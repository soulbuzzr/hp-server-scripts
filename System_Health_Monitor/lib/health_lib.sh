#!/bin/bash
set -u
set -o pipefail

# ================= RESOLVE HOME DIRECTORY for root user =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

BASE_DIR="$HOME/System_Scripts/System_Health_Monitor"
ENV_FILE="$BASE_DIR/env/system_health_bot.env"
CONF_FILE="$BASE_DIR/conf/system_limits.conf"

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
LOG_DIR="/var/log/system_health"
LOG_FILE="$LOG_DIR/health.log"

mkdir -p "$LOG_DIR"

log() {
  # Usage: log COMPONENT MESSAGE
  echo "$(date '+%F %T') [$1] $2" >> "$LOG_FILE"
}

# ================= TELEGRAM =================
tg_send() {
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=$1" \
    --data-urlencode "parse_mode=Markdown" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null
}

# ================= CONNECTIVITY =================
internet_up() {
  ping -c1 -W1 8.8.8.8 >/dev/null 2>&1
}

