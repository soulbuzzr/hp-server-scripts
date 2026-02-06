#!/bin/bash
set -u
set -o pipefail

# ================= LOAD ENV =================
ENV_FILE="/home/hpserver/System_scripts/system_health_bot.env"
if [ ! -r "$ENV_FILE" ]; then
  echo "ERROR: Missing env file: $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/etc/system_health.env
source "$ENV_FILE"

: "${TG_BOT_TOKEN:?Missing TG_BOT_TOKEN}"
: "${TG_CHAT_ID:?Missing TG_CHAT_ID}"

# ================= LOAD CONFIG =================
CONFIG_FILE="/home/hpserver/System_scripts/system_health_monitor.conf"
if [ ! -r "$CONFIG_FILE" ]; then
  echo "ERROR: Missing config file: $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck source=/home/hpserver/System_scripts/system_health_monitor.conf
source "$CONFIG_FILE"

: "${CPU_ACTIVE_THRESHOLD:?Missing CPU_ACTIVE_THRESHOLD}"

# ================= BASICS =================
HOST="🖥️ HP Linux Server"
LOG="/var/log/cpu_alerts.log"

log() {
  echo "$(date '+%F %T') $1" >> "$LOG"
}

tg_send() {
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT_ID" \
    -d text="$1" \
    -d parse_mode=Markdown \
    -d disable_web_page_preview=true >/dev/null
}

# ================= CONNECTIVITY CHECK =================
internet_up() {
  ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
}

until internet_up; do
  log "Waiting for internet before startup notify..."
  sleep 5
done

log "Internet is up, starting cpu load monitor..."
sleep 60

# ================= STARTUP NOTIFY =================
STARTUP_MSG="✅ *CPU Alerts Active*
$HOST
Monitoring: *1-minute average CPU usage*
Threshold: *${CPU_ACTIVE_THRESHOLD}%*"

log "CPU monitoring started (1-min avg)"
tg_send "$STARTUP_MSG"

# ================= CONTINUOUS MONITOR =================
while true; do
  # mpstat blocks for 60 seconds → this IS the timer
  CPU_AVG=$(mpstat 1 60 | awk '/Average/ {printf "%.2f",100-$NF}')
  CPU_INT=${CPU_AVG%.*}

  log "CPU_AVG_1MIN=${CPU_AVG}%"

  if [ "$CPU_INT" -ge "$CPU_ACTIVE_THRESHOLD" ]; then
    ALERT_MSG="🚨 *CPU ALERT*
$HOST
1-min Avg CPU Usage: *${CPU_AVG}%*
Threshold: *${CPU_ACTIVE_THRESHOLD}%*"

    log "CPU ALERT SENT (${CPU_AVG}%)"
    tg_send "$ALERT_MSG"
  fi
done
