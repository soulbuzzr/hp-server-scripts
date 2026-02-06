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
: "${REPORTED_UNCORRECT_THRESHOLD_INT:?Missing REPORTED_UNCORRECT_THRESHOLD_INT}"

# ================= BASICS =================
HOST="🖥️ HP Linux Server"
LOG="/var/log/hdd_internal_health_alerts.log"

HDD_DEV="/dev/sdb"
HDD_LABEL="Internal HDD"

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

# Temperature (attribute 194)
read_temp() {
  smartctl -A "$HDD_DEV" | awk '$1==194 {print $10+0}'
}

# Sector-related counters (RAW counters are correct here)
read_realloc() {
  smartctl -A "$HDD_DEV" | awk '/Reallocated_Sector_Ct/ {print $NF+0}'
}

read_pending() {
  smartctl -A "$HDD_DEV" | awk '/Current_Pending_Sector/ {print $NF+0}'
}

read_offline() {
  smartctl -A "$HDD_DEV" | awk '/Offline_Uncorrectable/ {print $NF+0}'
}

read_reported() {
  smartctl -A "$HDD_DEV" | awk '/Reported_Uncorrect/ {print $NF+0}'
}

# ================= CONNECTIVITY CHECK =================
internet_up() {
  ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
}

until internet_up; do
  log "Waiting for internet before startup notify..."
  sleep 5
done

log "Internet is up, starting internal health monitor..."
sleep 60

# ================= STARTUP NOTIFY =================
TEMP_START=$(read_temp 2>/dev/null || echo "N/A")
REALLOC_START=$(read_realloc 2>/dev/null || echo "N/A")
PENDING_START=$(read_pending 2>/dev/null || echo "N/A")
OFFLINE_START=$(read_offline 2>/dev/null || echo "N/A")
REPORTED_START=$(read_reported 2>/dev/null || echo "N/A")

STARTUP_MSG="💽 Internal HDD Health Alerts Active
$HOST
Device: Internal HDD
Temperature: *${TEMP_START}°C*
Reallocated Sectors: *${REALLOC_START}*
Pending Sectors: *${PENDING_START}*
Offline Uncorrectable: *${OFFLINE_START}*
Reported Uncorrectable: *${REPORTED_START}*
Monitoring interval: 6 hours"

log "Internal HDD health monitoring started"
tg_send "$STARTUP_MSG"

# ================= HDD HEALTH MONITOR =================
while true; do
  TEMP=$(read_temp)
  REALLOC=$(read_realloc)
  PENDING=$(read_pending)
  OFFLINE=$(read_offline)
  REPORTED=$(read_reported)

  log "HDD_STATUS temp=${TEMP}C realloc=${REALLOC} pending=${PENDING} offline=${OFFLINE} reported=${REPORTED}"

  # ---- Temperature ----
  if [ "$TEMP" -ge "$TEMP_THRESHOLD" ]; then
    ALERT_MSG="🔥 HDD TEMPERATURE ALERT
$HOST
Device: Internal HDD
Temperature: *${TEMP}°C*
Threshold: *${TEMP_THRESHOLD}°C*"

    log "HDD TEMP ALERT (${TEMP}C)"
    tg_send "$ALERT_MSG"
  fi

  # ---- Critical sector errors (binary) ----
  if [ "$REALLOC" -gt 0 ] || [ "$PENDING" -gt 0 ] || [ "$OFFLINE" -gt 0 ]; then
    ALERT_MSG="🚨 HDD SECTOR ERROR ALERT
$HOST
Device: Internal HDD
Reallocated: *${REALLOC}*
Pending: *${PENDING}*
Offline Uncorrectable: *${OFFLINE}*"

    log "HDD CRITICAL SECTOR ALERT"
    tg_send "$ALERT_MSG"
  fi

  # ---- Reported uncorrectable (threshold-based) ----
  if [ "$REPORTED" -gt "$REPORTED_UNCORRECT_THRESHOLD_INT" ]; then
    ALERT_MSG="⚠️ HDD REPORTED UNCORRECTABLE ALERT
$HOST
Device: Internal HDD
Reported Uncorrectable Errors: *${REPORTED}*
Threshold: *${REPORTED_UNCORRECT_THRESHOLD_INT}*"

    log "HDD REPORTED ALERT (${REPORTED})"
    tg_send "$ALERT_MSG"
  fi

  # Poll every 6 hours
  sleep 21600
done
