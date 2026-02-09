#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${REPORTED_UNCORRECT_THRESHOLD_INT:?Missing REPORTED_UNCORRECT_THRESHOLD_INT}"
: "${HOST_NAME:?Missing HOST_NAME}"

command -v smartctl >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
wait_for_network HDD_INTERNAL

# ================= STARTUP =================
startup_notify HDD_INTERNAL "💽 *Internal HDD Health Monitor Active*
$HOST_NAME

Monitoring:
• Reallocated sectors
• Pending sectors
• Offline uncorrectable
• Reported uncorrectable

Interval: *6 hours*"

# ================= INTERNAL HDD CHECK =================
check_internal_hdd() {
  local dev name realloc pending offline reported

  for dev in $(get_sata_devices); do
    name=$(disk_friendly_name "$dev")

    # Only internal HDDs
    [ "$name" = "Internal HDD" ] || continue

    realloc=$(read_realloc "$dev")
    pending=$(read_pending "$dev")
    offline=$(read_offline "$dev")
    reported=$(read_reported "$dev")

    log HDD_INTERNAL "[$name] realloc=${realloc} pending=${pending} offline=${offline} reported=${reported}"

    # ---- Critical sector errors ----
    if (( realloc > 0 || pending > 0 || offline > 0 )); then
      tg_send "🚨 *HDD SECTOR ERROR ALERT*
$HOST_NAME

Drive: *$name*
Reallocated: *$realloc*
Pending: *$pending*
Offline Uncorrectable: *$offline*"
    fi

    # ---- Reported uncorrectable threshold ----
    if (( reported > REPORTED_UNCORRECT_THRESHOLD_INT )); then
      tg_send "⚠️ *HDD REPORTED UNCORRECTABLE ALERT*
$HOST_NAME

Drive: *$name*
Reported Errors: *$reported*
Threshold: *$REPORTED_UNCORRECT_THRESHOLD_INT*"
    fi
  done
}

# ================= MAIN LOOP =================
while true; do
  check_internal_hdd
  sleep 21600   # 6 hours
done
