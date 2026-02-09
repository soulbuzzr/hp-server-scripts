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

LAST_HDD_CHECK=0
LAST_SSD_CHECK=0

# ================= MAIN LOOP =================
while true; do
  NOW=$(date +%s)

  for DEV in $(get_sata_devices); do
    NAME=$(disk_friendly_name "$DEV")
    TEMP=$(disk_temperature "$DEV" || true)
    [[ -n "$TEMP" ]] || continue

    if [[ "$NAME" == *SSD* ]]; then
      (( NOW - LAST_SSD_CHECK < SSD_INTERVAL_SEC )) && continue
      LAST_SSD_CHECK=$NOW

    elif [[ "$NAME" == *HDD* ]]; then
      (( NOW - LAST_HDD_CHECK < HDD_INTERVAL_SEC )) && continue
      LAST_HDD_CHECK=$NOW

    else
      continue
    fi

    log DISK_TEMP "[$NAME] temp=${TEMP}C"

    if (( TEMP > DISK_TEMP_WARN )); then
      tg_send "⚠️ *DISK TEMPERATURE HIGH*
$HOST_NAME

Drive: *$NAME*
Temperature: *${TEMP}°C*
Threshold: *${DISK_TEMP_WARN}°C*"
    fi
  done

  sleep 60
done
