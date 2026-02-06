#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/health_lib.sh"

# Required thresholds
: "${TEMP_THRESHOLD:?Missing TEMP_THRESHOLD}"
: "${REPORTED_UNCORRECT_THRESHOLD_INT:?Missing REPORTED_UNCORRECT_THRESHOLD_INT}"

# ================= BASICS =================
HOST="${HOST_NAME:-🖥️ HP Linux Server}"

HDD_DEV="/dev/sdb"
HDD_LABEL="Internal HDD"

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

until internet_up; do
  log HDD_INTERNAL "Waiting for internet before startup notify..."
  sleep 5
done

log HDD_INTERNAL "Internet is up, starting internal health monitor..."
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

log HDD_INTERNAL "Internal HDD health monitoring started"
tg_send "$STARTUP_MSG"

# ================= HDD HEALTH MONITOR =================
while true; do
  TEMP=$(read_temp)
  REALLOC=$(read_realloc)
  PENDING=$(read_pending)
  OFFLINE=$(read_offline)
  REPORTED=$(read_reported)

  log HDD_INTERNAL "HDD_STATUS temp=${TEMP}C realloc=${REALLOC} pending=${PENDING} offline=${OFFLINE} reported=${REPORTED}"

  # ---- Temperature ----
  if [ "$TEMP" -ge "$TEMP_THRESHOLD" ]; then
    ALERT_MSG="🔥 HDD TEMPERATURE ALERT
$HOST
Device: Internal HDD
Temperature: *${TEMP}°C*
Threshold: *${TEMP_THRESHOLD}°C*"

    log HDD_INTERNAL "HDD TEMP ALERT (${TEMP}C)"
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

    log HDD_INTERNAL "HDD CRITICAL SECTOR ALERT"
    tg_send "$ALERT_MSG"
  fi

  # ---- Reported uncorrectable (threshold-based) ----
  if [ "$REPORTED" -gt "$REPORTED_UNCORRECT_THRESHOLD_INT" ]; then
    ALERT_MSG="⚠️ HDD REPORTED UNCORRECTABLE ALERT
$HOST
Device: Internal HDD
Reported Uncorrectable Errors: *${REPORTED}*
Threshold: *${REPORTED_UNCORRECT_THRESHOLD_INT}*"

    log HDD_INTERNAL "HDD REPORTED ALERT (${REPORTED})"
    tg_send "$ALERT_MSG"
  fi

  # Poll every 6 hours
  sleep 21600
done
