#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${SSD_WEAR_VALUE_WARN:?Missing SSD_WEAR_VALUE_WARN}"
: "${HOST_NAME:?Missing HOST_NAME}"

command -v smartctl >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
wait_for_network SSD

# ================= STARTUP =================
startup_notify SSD "💾 *SSD Health Monitor Active*
$HOST_NAME

Monitoring:
• Reallocated sectors
• Media wearout (life remaining)

Interval: *6 hours*"

# ================= SSD CHECK =================
check_ssd_health() {
  local dev name realloc wear

  for dev in $(get_sata_devices); do
    name=$(disk_friendly_name "$dev")

    # Only internal SSDs
    [ "$name" = "SSD" ] || continue

    realloc=$(read_realloc "$dev")
    wear=$(read_wear_value "$dev")

    log SSD "[$name] realloc=${realloc} wear=${wear}"

    # ---- Reallocated sectors ----
    if (( realloc > 0 )); then
      tg_send "🚨 *SSD REALLOCATED SECTORS ALERT*
$HOST_NAME

Drive: *$name*
Reallocated Sectors: *$realloc*"
    fi

    # ---- Wear indicator (life remaining %) ----
    if (( wear < SSD_WEAR_VALUE_WARN )); then
      tg_send "⚠️ *SSD WEAR ALERT*
$HOST_NAME

Drive: *$name*
Life Remaining: *${wear}%*
Warning Threshold: *${SSD_WEAR_VALUE_WARN}%*"
    fi
  done
}

# ================= MAIN LOOP =================
while true; do
  check_ssd_health
  sleep 21600   # 6 hours
done
