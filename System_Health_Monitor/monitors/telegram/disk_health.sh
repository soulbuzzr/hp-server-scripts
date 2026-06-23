#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${BOOT_SSD_REALLOC:?Missing BOOT_SSD_REALLOC}"
: "${BOOT_SSD_WEAR:?Missing BOOT_SSD_WEAR}"

: "${IMMICH_SSD_REALLOC:?Missing IMMICH_SSD_REALLOC}"
: "${IMMICH_SSD_WEAR:?Missing IMMICH_SSD_WEAR}"

: "${CAMERA_HDD_REALLOC:?Missing CAMERA_HDD_REALLOC}"
: "${CAMERA_HDD_PENDING:?Missing CAMERA_HDD_PENDING}"
: "${CAMERA_HDD_OFFLINE:?Missing CAMERA_HDD_OFFLINE}"
: "${CAMERA_HDD_REPORTED:?Missing CAMERA_HDD_REPORTED}"

: "${DATA_HDD_REALLOC:?Missing DATA_HDD_REALLOC}"
: "${DATA_HDD_PENDING:?Missing DATA_HDD_PENDING}"
: "${DATA_HDD_OFFLINE:?Missing DATA_HDD_OFFLINE}"
: "${DATA_HDD_REPORTED:?Missing DATA_HDD_REPORTED}"

: "${DISK_CHECK_INTERVAL:?Missing DISK_CHECK_INTERVAL}"    

: "${HOST_NAME:?Missing HOST_NAME}"

# ================= WAIT FOR NETWORK =================
wait_for_network SATA_HEALTH

# ================= STARTUP =================
startup_notify SATA_HEALTH "💽 *SATA Disk Health Monitor Active*
$HOST_NAME

Monitoring:
• SSD: reallocated sectors, wear level
• HDD: reallocated, pending, offline, reported uncorrectable sectors

Interval: *${DISK_CHECK_INTERVAL} hour(s)*"

# ================= INTERVALS =================
DISK_CHECK_INTERVAL_SEC=$(( DISK_CHECK_INTERVAL * 3600 ))

# ================= SATA HEALTH CHECK =================
check_sata_health() {
    local dev name
    local realloc pending offline reported wear
    local BASE_REALLOC BASE_PENDING BASE_OFFLINE BASE_REPORTED BASE_WEAR

    for dev in $(get_sata_devices); do
        name=$(disk_friendly_name "$dev")

        # ================= SSD =================
        if wear=$(read_wear_value "$dev" 2>/dev/null); then

            realloc=$(read_realloc "$dev")

            read BASE_REALLOC BASE_PENDING BASE_OFFLINE BASE_REPORTED BASE_WEAR \
                <<< "$(get_disk_Thresholds "$name")"

            log SATA_HEALTH "[$name] realloc=${realloc} wear=${wear}"

            if (( realloc > BASE_REALLOC )); then
                tg_send_disk "🚨 *SSD REALLOCATED SECTORS ALERT*
$HOST_NAME

Drive: *$name*
Current Reallocated Sectors: *$realloc*
Threshold: *$BASE_REALLOC*"
            fi

            if (( wear < BASE_WEAR )); then
                tg_send_disk "⚠ *SSD WEAR ALERT*
$HOST_NAME

Drive: *$name*
Current Life Remaining: *${wear}%*
Warning Threshold: *${BASE_WEAR}%*"
            fi

        # ================= HDD =================
        else

            realloc=$(read_realloc "$dev")
            pending=$(read_pending "$dev")
            offline=$(read_offline "$dev")
            reported=$(read_reported "$dev")

            read BASE_REALLOC BASE_PENDING BASE_OFFLINE BASE_REPORTED BASE_WEAR \
                <<< "$(get_disk_Thresholds "$name")"

            log SATA_HEALTH "[$name] realloc=${realloc} pending=${pending} offline=${offline} reported=${reported}"

            if (( realloc > BASE_REALLOC || pending > BASE_PENDING || offline > BASE_OFFLINE )); then
                tg_send_disk "🚨 *HDD SECTOR ERROR ALERT*
$HOST_NAME

Drive: *$name*

Current:
• Reallocated sectors: *$realloc*
• Pending sectors: *$pending*
• Offline uncorrectable sectors: *$offline*

Threshold:
• Reallocated sectors: *$BASE_REALLOC*
• Pending sectors: *$BASE_PENDING*
• Offline uncorrectable sectors: *$BASE_OFFLINE*"
            fi

            if (( reported > BASE_REPORTED )); then
                tg_send_disk "⚠ *HDD REPORTED UNCORRECTABLE SECTOR ALERT*

$HOST_NAME

Drive: *$name*
Current Reported Errors: *$reported*
Warning Threshold: *$BASE_REPORTED*"
            fi
        fi
    done
}

# ================= MAIN LOOP =================
while true; do
  check_sata_health
  sleep ${DISK_CHECK_INTERVAL_SEC}
done
