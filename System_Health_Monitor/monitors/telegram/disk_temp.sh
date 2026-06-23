#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${HDD_CHECK_INTERVAL:?Missing HDD_CHECK_INTERVAL}"    
: "${SSD_CHECK_INTERVAL:?Missing SSD_CHECK_INTERVAL}"    
: "${DISK_TEMP_WARN:?Missing DISK_TEMP_WARN}"            
: "${HOST_NAME:?Missing HOST_NAME}"

# ================= WAIT FOR NETWORK =================
wait_for_network DISK_TEMP

# ================= STARTUP =================
startup_notify DISK_TEMP "💾 *Disk Temperature Monitor Active*
$HOST_NAME

Threshold:
• Disk temperature > *${DISK_TEMP_WARN}°C*
Intervals:
• HDD: *${HDD_CHECK_INTERVAL} minute(s)*
• SSD: *${SSD_CHECK_INTERVAL} minute(s)*"

# ================= INTERVALS =================
HDD_INTERVAL_SEC=$(( HDD_CHECK_INTERVAL * 60 ))
SSD_INTERVAL_SEC=$(( SSD_CHECK_INTERVAL * 60 ))

# ================= MAIN LOOP =================
# Last temperature check timestamp per device
declare -A LAST_CHECK

while true; do
  NOW=$(date +%s)

  for DEV in $(get_sata_devices); do
    NAME=$(disk_friendly_name "$DEV")

    if [[ "$NAME" == *SSD* ]]; then
      (( NOW - ${LAST_CHECK[$DEV]:-0} < SSD_INTERVAL_SEC )) && continue

    elif [[ "$NAME" == *HDD* ]]; then
      (( NOW - ${LAST_CHECK[$DEV]:-0} < HDD_INTERVAL_SEC )) && continue

    else
      continue
    fi

    # Query SMART reported temperature
    TEMP=$(disk_temperature "$DEV" || true)
    [[ -n "$TEMP" ]] || continue

    # Record last successful temperature check time
    LAST_CHECK[$DEV]=$NOW
    
    log DISK_TEMP "[$NAME] temp=${TEMP}C"

    if (( TEMP > DISK_TEMP_WARN )); then
      tg_send_disk_disk "⚠️ *DISK TEMPERATURE HIGH*
$HOST_NAME

Drive: *$NAME*
Temperature: *${TEMP}°C*
Threshold: *${DISK_TEMP_WARN}°C*"
    fi
  done

  sleep 60
done
