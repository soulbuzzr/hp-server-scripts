#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/health_lib.sh"

# Required thresholds
: "${TEMP_THRESHOLD:?Missing TEMP_THRESHOLD}"
: "${SSD_WEAR_VALUE_WARN:?Missing SSD_WEAR_VALUE_WARN}"

# ================= BASICS =================
HOST="${HOST_NAME:-🖥️ HP Linux Server}"

SSD_DEV="/dev/sda"

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

until internet_up; do
  log SSD "Waiting for internet before startup notify..."
  sleep 5
done

log SSD "Internet is up, starting ssd health monitor..."
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

log SSD "SSD health monitoring started"
tg_send "$STARTUP_MSG"

# ================= SSD HEALTH MONITOR =================
while true; do
  TEMP=$(read_temp)
  REALLOC_VAL=$(read_realloc_value)
  WEAR_VAL=$(read_wear_value)

  log SSD "SSD_STATUS temp=${TEMP}C realloc_val=${REALLOC_VAL} wear_val=${WEAR_VAL}"

  # ---- Temperature alert ----
  if [ "$TEMP" -ge "$TEMP_THRESHOLD" ]; then
    ALERT_MSG="🔥 SSD TEMPERATURE ALERT
$HOST
Device: SSD
Temperature: ${TEMP}°C
Threshold: ${TEMP_THRESHOLD}°C"

    log SSD "SSD TEMP ALERT (${TEMP}C)"
    tg_send "$ALERT_MSG"
  fi

  # ---- Reallocated sectors (ONLY if > 0) ----
  if [ "$REALLOC_VAL" -gt 0 ]; then
    ALERT_MSG="🚨 SSD REALLOCATED SECTORS ALERT
$HOST
Device: SSD
Reallocated Sector VALUE: ${REALLOC_VAL}"

    log SSD "SSD REALLOC ALERT (${REALLOC_VAL})"
    tg_send "$ALERT_MSG"
  fi

  # ---- Wear indicator (life remaining %) ----
  if [ "$WEAR_VAL" -lt "$SSD_WEAR_VALUE_WARN" ]; then
    ALERT_MSG="⚠️ SSD WEAR ALERT
$HOST
Device: SSD 
Life Remaining: ${WEAR_VAL}%
Warning threshold: ${SSD_WEAR_VALUE_WARN}%"

    log SSD "SSD WEAR ALERT (${WEAR_VAL}%)"
    tg_send "$ALERT_MSG"
  fi

  # Poll every six hours
  sleep 21600
done
