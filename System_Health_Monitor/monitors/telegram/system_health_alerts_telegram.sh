#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/health_lib.sh"

HOSTNAME="${HOST_NAME:-🖥️  HP Linux Server}"

# ================= STARTUP NOTIFY =================
startup_notify() {
  MSG="✅ *HP SERVER MONITOR STARTED*
Host: $HOSTNAME
Monitoring:
- CPU avg (1 min)
- Disk temp (5 sec)
- Disk health (5 min)
Time: $(date '+%F %T')"

  log ALERTS "Server Monitor started"
  tg_send "$MSG"
}

# ================= CPU CHECK (1 MIN AVG) =================
cpu_check() {
  CPU_AVG=$(mpstat 1 60 | awk '/Average/ {printf "%.2f",100-$NF}')
  CPU_INT=${CPU_AVG%.*}

  log ALERTS "CPU_AVG_1MIN=${CPU_AVG}%"

  if [ "$CPU_INT" -ge "$CPU_ACTIVE_THRESHOLD" ]; then
    MSG="🚨 *CPU ALERT*
Host: $HOSTNAME
1-min Avg CPU: ${CPU_AVG}%"

    log ALERTS "$MSG"
    tg_send "$MSG"
  fi
}

# ================= DISK MAP =================
declare -A DISK_LABELS=(
  [/dev/sda]="SSD"
  [/dev/sdb]="Internal HDD"
  [/dev/sdc]="External HDD"
)

# ================= DISK TEMP CHECK (5 SEC) =================
disk_temp_check() {
  for DEV in /dev/sda /dev/sdb /dev/sdc; do
    [ -b "$DEV" ] || continue

    LABEL="${DISK_LABELS[$DEV]:-$DEV}"

    TEMP=$(smartctl -A "$DEV" | awk '$1==194 {print $10+0}')
    [ -n "$TEMP" ] || continue

    log ALERTS "DISK_TEMP [$LABEL]: ${TEMP}C"

    if [ "$TEMP" -ge "$DISK_TEMP_WARN" ]; then
      MSG="⚠️ *DISK TEMP HIGH*
$LABEL
Temperature: ${TEMP}°C"

      log ALERTS "$MSG"
      tg_send "$MSG"
    fi
  done
}

# ================= DISK HEALTH CHECK (5 MIN) =================
disk_health_check() {
  for DEV in /dev/sda /dev/sdb /dev/sdc; do
    [ -b "$DEV" ] || continue

    LABEL="${DISK_LABELS[$DEV]:-$DEV}"

    # -------- SSD --------
    if [ "$DEV" = "/dev/sda" ]; then
      REALLOC=$(smartctl -A "$DEV" | awk '/Reallocated_Sector_Ct/ {print $NF+0}')
      WEAR=$(smartctl -A "$DEV" | awk '/Media_Wearout_Indicator/ {print $NF+0}')

      log ALERTS "SSD_HEALTH [$LABEL]: realloc=${REALLOC} wear=${WEAR}"

      if [ "$REALLOC" -gt 0 ]; then
        MSG="🚨 *SSD REALLOCATED SECTORS*
$LABEL
Reallocated: ${REALLOC}"
        log ALERTS "$MSG"
        tg_send "$MSG"
      fi

      if [ "$WEAR" -gt 0 ]; then
        MSG="⚠️ *SSD WEAR INDICATOR*
$LABEL
Media Wearout: ${WEAR}"
        log ALERTS "$MSG"
        tg_send "$MSG"
      fi
    fi

    # -------- HDDs --------
    if [ "$DEV" = "/dev/sdb" ] || [ "$DEV" = "/dev/sdc" ]; then
      REALLOC=$(smartctl -A "$DEV" | awk '/Reallocated_Sector_Ct/ {print $NF+0}')
      PENDING=$(smartctl -A "$DEV" | awk '/Current_Pending_Sector/ {print $NF+0}')
      OFFLINE=$(smartctl -A "$DEV" | awk '/Offline_Uncorrectable/ {print $NF+0}')
      REPORTED=$(smartctl -A "$DEV" | awk '/Reported_Uncorrect/ {print $NF+0}')

      log ALERTS "HDD_HEALTH [$LABEL]: realloc=${REALLOC} pending=${PENDING} offline=${OFFLINE} reported=${REPORTED}"

      if [ "$REALLOC" -gt 0 ] || [ "$PENDING" -gt 0 ] || [ "$OFFLINE" -gt 0 ] || [ "$REPORTED" -gt 0 ]; then
        MSG="🚨 *HDD SECTOR ERRORS*
$LABEL
Reallocated: ${REALLOC}
Pending: ${PENDING}
Offline Uncorrectable: ${OFFLINE}
Reported Uncorrectable: ${REPORTED}"
        log ALERTS "$MSG"
        tg_send "$MSG"
      fi
    fi
  done
}

# ================= MAIN LOOP =================

until internet_up; do
  log ALERTS "Waiting for internet..."
  sleep 5
done

log ALERTS "Internet up, waiting 60 seconds before starting startup notify..."
sleep 60
startup_notify

CPU_TIMER=0
DISK_HEALTH_TIMER=0

while true; do
  disk_temp_check

  if (( CPU_TIMER >= 60 )); then
    cpu_check
    CPU_TIMER=0
  fi

  if (( DISK_HEALTH_TIMER >= 300 )); then
    disk_health_check
    DISK_HEALTH_TIMER=0
  fi

  sleep 5
  CPU_TIMER=$((CPU_TIMER + 5))
  DISK_HEALTH_TIMER=$((DISK_HEALTH_TIMER + 5))
done
