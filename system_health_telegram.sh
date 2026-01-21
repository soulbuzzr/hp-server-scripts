#!/bin/bash
set -euo pipefail

# ================= CONFIG =================
# Telegram notification integration (from cron env)
: "${TG_BOT_TOKEN:?TG_BOT_TOKEN not set}"
: "${TG_CHAT_ID:?TG_CHAT_ID not set}"
LOG_FILE="/var/log/system_health.log"

# ================= BASICS =================
HOST='💻  HP Linux Server'
TS=$(date '+%Y-%m-%d %H:%M:%S')
UPTIME=$(uptime -p | sed 's/^up //')

# ================= EMOJI HELPERS =================
cpu_emoji() {
  if [ "$1" -lt 20 ]; then echo "🟢"
  elif [ "$1" -lt 60 ]; then echo "🟡"
  else echo "🔴"; fi
}

temp_emoji() {
  if [ "$1" -lt 45 ]; then echo "🟢"
  elif [ "$1" -lt 55 ]; then echo "🟡"
  else echo "🔴"; fi
}

health_emoji() {
  if [ "$1" -eq 0 ]; then echo "🟢"
  elif [ "$1" -lt 10 ]; then echo "🟡"
  else echo "🔴"; fi
}

# ================= CPU USAGE (1 min avg) =================
CPU_ACTIVE=$(mpstat 1 60 | awk '/Average/ {printf "%d",100-$NF}')
CPU_E=$(cpu_emoji "${CPU_ACTIVE%.*}")


# ================= DISK METRICS =================
disk_metrics() {
  DEV="$1"
  LABEL="$2"

  TEMP=$(smartctl -A "$DEV" | awk '$1==194 {print $10+0}')
  REALLOC=$(smartctl -A "$DEV" | awk '/Reallocated_Sector_Ct/ {print $NF+0}')

  TEMP_E=$(temp_emoji "$TEMP")
  REALLOC_E=$(health_emoji "$REALLOC")

  printf "💽 *%s*\n• 🌡️ Temp: %s°C %s\n• ♻️ Reallocated: %s %s\n" \
    "$LABEL" "$TEMP" "$TEMP_E" "$REALLOC" "$REALLOC_E"
}

DISK_BLOCK=""

[ -b /dev/sda ] && DISK_BLOCK+="$(disk_metrics /dev/sda "sda – SSD")"$'\n'
[ -b /dev/sdb ] && DISK_BLOCK+="$(disk_metrics /dev/sdb "sdb – Internal HDD")"$'\n'
[ -b /dev/sdc ] && DISK_BLOCK+="$(disk_metrics /dev/sdc "sdc – External HDD")"$'\n'

# ================= LOG (FULL DETAILS) =================
LOG_MSG="$HOST
CPU Usage: $CPU_ACTIVE%
$DISK_BLOCK
$TS
--------------------------------------------------"

echo "$LOG_MSG" >> "$LOG_FILE"

# ================= TELEGRAM =================
TG_MSG="*$HOST*

⏱️ *Uptime*
  $UPTIME

🧮 *CPU Usage*
• $CPU_ACTIVE% $CPU_E

🗄️ *Disk Health*
$DISK_BLOCK
🕒 *$TS*"

curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
  -d chat_id="$TG_CHAT_ID" \
  -d text="$TG_MSG" \
  -d parse_mode=Markdown \
  -d disable_web_page_preview=true >/dev/null