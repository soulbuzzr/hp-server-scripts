#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${SSD_WEAR_VALUE_WARN:?Missing SSD_WEAR_VALUE_WARN}"
: "${REPORTED_UNCORRECT_THRESHOLD_INT:?Missing REPORTED_UNCORRECT_THRESHOLD_INT}"
: "${HOST_NAME:?Missing HOST_NAME}"

# ================= WAIT FOR NETWORK =================
wait_for_network SATA_HEALTH

# ================= STARTUP =================
startup_notify SATA_HEALTH "💽 *SATA Disk Health Monitor Active*
$HOST_NAME

Monitoring:
• SSD: reallocated sectors, wear level
• HDD: reallocated, pending, offline, reported uncorrectable

Interval: *6 hours*"

# ================= SATA HEALTH CHECK =================
check_sata_health() {
  local dev name
  local realloc pending offline reported wear

  for dev in $(get_sata_devices); do
    name=$(disk_friendly_name "$dev")

    # ================= SSD =================
    if [[ "$name" == "SSD" ]]; then
      realloc=$(read_realloc "$dev")
      wear=$(read_wear_value "$dev")

      log SATA_HEALTH "[SSD] realloc=${realloc} wear=${wear}"

      if (( realloc > 0 )); then
        tg_send "🚨 *SSD REALLOCATED SECTORS ALERT*
$HOST_NAME

Drive: *SSD*
Reallocated Sectors: *$realloc*"
      fi

      if (( wear < SSD_WEAR_VALUE_WARN )); then
        tg_send "⚠ *SSD WEAR ALERT*
$HOST_NAME

Drive: *SSD*
Life Remaining: *${wear}%*
Warning Threshold: *${SSD_WEAR_VALUE_WARN}%*"
      fi

    # ================= INTERNAL HDD =================
    elif [[ "$name" == "Internal HDD" ]]; then
      realloc=$(read_realloc "$dev")
      pending=$(read_pending "$dev")
      offline=$(read_offline "$dev")
      reported=$(read_reported "$dev")

      log SATA_HEALTH "[HDD] realloc=${realloc} pending=${pending} offline=${offline} reported=${reported}"

      if (( realloc > 0 || pending > 0 || offline > 0 )); then
        tg_send "🚨 *HDD SECTOR ERROR ALERT*
$HOST_NAME

Drive: *Internal HDD*
Reallocated: *$realloc*
Pending: *$pending*
Offline Uncorrectable: *$offline*"
      fi

      if (( reported > REPORTED_UNCORRECT_THRESHOLD_INT )); then
        tg_send "⚠ *HDD REPORTED UNCORRECTABLE ALERT*
$HOST_NAME

Drive: *Internal HDD*
Reported Errors: *$reported*
Threshold: *$REPORTED_UNCORRECT_THRESHOLD_INT*"
      fi
    fi
  done
}

# ================= MAIN LOOP =================
while true; do
  check_sata_health
  sleep 21600   # 6 hours
done
