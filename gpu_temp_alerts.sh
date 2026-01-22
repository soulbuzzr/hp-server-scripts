#!/bin/bash
set -u
set -o pipefail

# ================= LOAD ENV =================
ENV_FILE="/home/hpserver/System_scripts/system_health_bot.env"
if [ ! -r "$ENV_FILE" ]; then
  echo "ERROR: Missing env file: $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/home/hpserver/System_scripts/system_health.env
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

: "${GPU_TEMP_THRESHOLD:?Missing GPU_TEMP_THRESHOLD}"

# ================= BASICS =================
HOST="🖥️ HP Linux Server"
LOG="/var/log/gpu_temp_alerts.log"

GPU_TEMP_PATH="/sys/class/hwmon/hwmon4/temp1_input"

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

# ================= GPU TEMP READER =================
read_gpu_temp() {
  [ -r "$GPU_TEMP_PATH" ] || return
  echo $(( $(cat "$GPU_TEMP_PATH") / 1000 ))
}

# ================= CONNECTIVITY CHECK =================
internet_up() {
  ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
}

until internet_up; do
  log "Waiting for internet before startup notify..."
  sleep 5
done

log "Internet is up, starting gpu temp monitor..."
sleep 60

# ================= STARTUP NOTIFY =================
START_TEMP=$(read_gpu_temp || echo "N/A")

STARTUP_MSG="🎮 *GPU Temperature Alerts Active*
$HOST
Current GPU Temp: *${START_TEMP}°C*
Monitoring: *30-second average GPU temperature*
Threshold: *${GPU_TEMP_THRESHOLD}°C*"

log "GPU temperature monitoring started (30-sec avg)"
tg_send "$STARTUP_MSG"

# ================= CONTINUOUS MONITOR =================
while true; do
  SUM=0
  COUNT=0

  # Collect 30 samples, 1 per second
  for _ in $(seq 1 30); do
    TEMP=$(read_gpu_temp)
    [ -n "$TEMP" ] || continue
    SUM=$((SUM + TEMP))
    COUNT=$((COUNT + 1))
    sleep 1
  done

  # No samples → skip safely
  [ "$COUNT" -eq 0 ] && continue

  # Integer average (logic)
  AVG_TEMP_INT=$((SUM / COUNT))

  # Float average (display)
  AVG_TEMP_FLOAT=$(awk -v s="$SUM" -v c="$COUNT" \
    'BEGIN { printf "%.2f", s / c }')

  log "GPU_TEMP_AVG_30SEC=${AVG_TEMP_FLOAT}C"

  if [ "$AVG_TEMP_INT" -ge "$GPU_TEMP_THRESHOLD" ]; then
    ALERT_MSG="🔥 *GPU TEMPERATURE ALERT*
$HOST
30-sec Avg GPU Temp: *${AVG_TEMP_FLOAT}°C*
Threshold: *${GPU_TEMP_THRESHOLD}°C*"

    log "GPU TEMP ALERT SENT (${AVG_TEMP_FLOAT}C)"
    tg_send "$ALERT_MSG"
  fi
done
