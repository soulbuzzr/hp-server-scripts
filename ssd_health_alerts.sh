#!/bin/bash
set -u
set -o pipefail

# ================= LOAD ENV =================
ENV_FILE="/home/hpserver/System_scripts/system_health_bot.env"
if [ ! -r "$ENV_FILE" ]; then
  echo "ERROR: Missing env file: $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/home/hpserver/System_scripts/system_health_bot.env
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

# Required thresholds
: "${TEMP_THRESHOLD:?Missing TEMP_THRESHOLD}"
: "${SSD_WEAR_VALUE_WARN:?Missing SSD_WEAR_VALUE_WARN}"

# ================= BASICS =================
HOST="🖥️ HP Linux Server"
LOG="/var/log/ssd_health_alerts.log"

SSD_DEV="/dev/sda"

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

# ================= SMART READERS =================

# Temperature (attribute 194 – value field is temperature)
read_temp() {
  smartctl -A "$SSD_DEV" | awk '$1==194 {print $10}'
}

# Reallocated sectors – CURRENT VALUE, binary logic
read_realloc_value() {
  smartctl -A "$SSD_DEV" | awk '/Reallocated_Sector_Ct/ {print $NF}'
}

# Media wearout – CURRENT VALUE (life remaining %)
read_wear_value() {
  smartctl -A "$SSD_DEV" | awk '/Media_Wearout_Indicator/ {print $4+0}'
}

# ================= CONNECTIVITY CHECK =================
internet_up() {
  ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
}

until internet_up; do
  log "Waiting for internet before startup notify..."
  sleep 5
done

log "Internet is up, starting ssd health monitor..."
sleep 60

# ================= STARTUP NOTIFY =================
TEMP_START=$(read_temp 2>/dev/null || echo "N/A")
REALLOC_VAL_START=$(read_realloc_value 2>/dev/null || echo "N/A")
WEAR_VAL_START=$(read_wear_value 2>/dev/null || echo "N/A")

STARTUP_MSG="💾 SSD Health and Temp Alerts Active
$HOST
Device: *SSD*
Temperature: *${TEMP_START}°C*
Reallocated Sector VALUE: *${REALLOC_VAL_START}*
Media Wearout VALUE (life remaining): *${WEAR_VAL_START}%*
Monitoring interval: 6 hours"

log "SSD health monitoring started"
tg_send "$STARTUP_MSG"

# ================= SSD HEALTH MONITOR =================
while true; do
  TEMP=$(read_temp)
  REALLOC_VAL=$(read_realloc_value)
  WEAR_VAL=$(read_wear_value)

  log "SSD_STATUS temp=${TEMP}C realloc_val=${REALLOC_VAL} wear_val=${WEAR_VAL}"

  # ---- Temperature alert ----
  if [ "$TEMP" -ge "$TEMP_THRESHOLD" ]; then
    ALERT_MSG="🔥 SSD TEMPERATURE ALERT
$HOST
Device: SSD
Temperature: ${TEMP}°C
Threshold: ${TEMP_THRESHOLD}°C"

    log "SSD TEMP ALERT (${TEMP}C)"
    tg_send "$ALERT_MSG"
  fi

  # ---- Reallocated sectors (ONLY if > 0) ----
  if [ "$REALLOC_VAL" -gt 0 ]; then
    ALERT_MSG="🚨 SSD REALLOCATED SECTORS ALERT
$HOST
Device: SSD
Reallocated Sector VALUE: ${REALLOC_VAL}"

    log "SSD REALLOC ALERT (${REALLOC_VAL})"
    tg_send "$ALERT_MSG"
  fi

  # ---- Wear indicator (life remaining %) ----
  if [ "$WEAR_VAL" -lt "$SSD_WEAR_VALUE_WARN" ]; then
    ALERT_MSG="⚠️ SSD WEAR ALERT
$HOST
Device: SSD 
Life Remaining: ${WEAR_VAL}%
Warning threshold: ${SSD_WEAR_VALUE_WARN}%"

    log "SSD WEAR ALERT (${WEAR_VAL}%)"
    tg_send "$ALERT_MSG"
  fi

  # Poll every six hours
  sleep 21600
done
