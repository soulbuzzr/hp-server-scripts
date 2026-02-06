#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${DISK_TEMP_WARN:?Missing DISK_TEMP_WARN}"
: "${HOST_NAME:?Missing HOST_NAME}"

command -v smartctl >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log DISK_TEMP "Waiting for internet..."
  sleep 5
done

# ================= STARTUP NOTIFY =================
log DISK_TEMP "SATA DISK temperature monitor started"
tg_send "💾 *DISK Temperature Monitor Active*
$HOST_NAME
Threshold: *${DISK_TEMP_WARN}°C*"

# ================= TEMP READER =================
read_sata_temp() {
  local dev="$1"
  smartctl -A "$dev" 2>/dev/null | awk '$1==194 {print $10+0}'
}

# ================= MAIN LOOP =================
while true; do
  for DEV in $(get_sata_devices); do
    NAME=$(disk_friendly_name "$DEV")

    # Only alert for INTERNAL disks (SSD + WD HDD)
    case "$NAME" in
      "SSD"|"Internal HDD")
        TEMP=$(read_sata_temp "$DEV")
        ;;
      *)
        continue
        ;;
    esac

    [ -n "$TEMP" ] || continue

    log DISK_TEMP "[$NAME] temp=${TEMP}C"

    if (( TEMP > DISK_TEMP_WARN )); then
      tg_send "⚠️ *DISK TEMP HIGH*
$HOST_NAME
Drive: *$NAME*
Temperature: *${TEMP}°C*
Threshold: *${DISK_TEMP_WARN}°C*"
    fi
  done

  sleep 60
done
