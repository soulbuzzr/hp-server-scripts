#!/bin/bash
set -u
set -o pipefail

# ================= REQUIRED ENV =================
: "${TG_BOT_TOKEN:?TG_BOT_TOKEN is not set}"
: "${TG_CHAT_ID:?TG_CHAT_ID is not set}"

HOSTNAME='🖥️  HP Linux Server'
LOG_FILE="/var/log/system_health_alerts.log"

# ================= LOAD CONFIG =================
CONFIG_FILE="/home/hpserver/System_scripts/system_health_monitor.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing config: $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck source
source "$CONFIG_FILE"

# ================= HELPERS =================
log() {
  echo "$(date '+%F %T') $1" >> "$LOG_FILE"
}

tg_send() {
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT_ID" \
    -d text="$1" \
    -d parse_mode=Markdown \
    -d disable_web_page_preview=true >/dev/null
}

# ================= STARTUP NOTIFY =================
startup_notify() {
  MSG="✅ *HP SERVER MONITOR STARTED*
Host: $HOSTNAME
Monitoring:
- CPU avg (1 min)
- Disk temp (5 sec)
- Disk health (5 min)
Time: $(date '+%F %T')"

  log "Server Monitor started"
  tg_send "$MSG"
}

# ================= CPU CHECK (1 MIN AVG) =================
cpu_check() {
  CPU_AVG=$(mpstat 1 60 | awk '/Average/ {printf "%.2f",100-$NF}')
  CPU_INT=${CPU_AVG%.*}

  log "CPU_AVG_1MIN=${CPU_AVG}%"

  if [ "$CPU_INT" -ge "$CPU_ACTIVE_THRESHOLD" ]; then
    MSG="🚨 *CPU ALERT*
Host: $HOSTNAME
1-min Avg CPU: ${CPU_AVG}%"

    log "$MSG"
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

    log "DISK_TEMP [$LABEL]: ${TEMP}C"

    if [ "$TEMP" -ge "$DISK_TEMP_WARN" ]; then
      MSG="⚠️ *DISK TEMP HIGH*
$LABEL
Temperature: ${TEMP}°C"

      log "$MSG"
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

      log "SSD_HEALTH [$LABEL]: realloc=${REALLOC} wear=${WEAR}"

      if [ "$REALLOC" -gt 0 ]; then
        MSG="🚨 *SSD REALLOCATED SECTORS*
$LABEL
Reallocated: ${REALLOC}"
        log "$MSG"
        tg_send "$MSG"
      fi

      if [ "$WEAR" -gt 0 ]; then
        MSG="⚠️ *SSD WEAR INDICATOR*
$LABEL
Media Wearout: ${WEAR}"
        log "$MSG"
        tg_send "$MSG"
      fi
    fi

    # -------- HDDs --------
    if [ "$DEV" = "/dev/sdb" ] || [ "$DEV" = "/dev/sdc" ]; then
      REALLOC=$(smartctl -A "$DEV" | awk '/Reallocated_Sector_Ct/ {print $NF+0}')
      PENDING=$(smartctl -A "$DEV" | awk '/Current_Pending_Sector/ {print $NF+0}')
      OFFLINE=$(smartctl -A "$DEV" | awk '/Offline_Uncorrectable/ {print $NF+0}')
      REPORTED=$(smartctl -A "$DEV" | awk '/Reported_Uncorrect/ {print $NF+0}')

      log "HDD_HEALTH [$LABEL]: realloc=${REALLOC} pending=${PENDING} offline=${OFFLINE} reported=${REPORTED}"

      if [ "$REALLOC" -gt 0 ] || [ "$PENDING" -gt 0 ] || [ "$OFFLINE" -gt 0 ] || [ "$REPORTED" -gt 0 ]; then
        MSG="🚨 *HDD SECTOR ERRORS*
$LABEL
Reallocated: ${REALLOC}
Pending: ${PENDING}
Offline Uncorrectable: ${OFFLINE}
Reported Uncorrectable: ${REPORTED}"
        log "$MSG"
        tg_send "$MSG"
      fi
    fi
  done
}

# ================= CONNECTIVITY CHECK =================
internet_up() {
  ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
}

# ================= MAIN LOOP =================

until internet_up; do
  log "Waiting for internet..."
  sleep 5
done

log "Internet up, waiting 60 seconds before starting startup notify..."
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
