#!/bin/bash
set -euo pipefail

# ================= LOAD SHARED LIB =================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/health_lib.sh"

LOG_FILE="/var/log/system_health.log"

# ================= BASICS =================
HOST="${HOST_NAME:-💻  HP Linux Server}"
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
CPU_ACTIVE=$(mpstat 1 60 | awk '/Average/ {printf "%.2f",100-$NF}')

# extract integer part for emoji logic
CPU_INT=${CPU_ACTIVE%.*}
CPU_E=$(cpu_emoji "$CPU_INT")


# ================= DISK METRICS =================
disk_metrics() {
  DEV="$1"
  LABEL="$2"

  TEMP=$(smartctl -A "$DEV" | awk '$1==194 {print $10+0}')
  REALLOC=$(smartctl -A "$DEV" | awk '/Reallocated_Sector_Ct/ {print $NF+0}')

  TEMP_E=$(temp_emoji "$TEMP")
  REALLOC_E=$(health_emoji "$REALLOC")

  printf "    💽 *%s*\n        • 🌡️ Temp: %s°C %s\n        • ♻️ Reallocated: %s %s\n" \
    "$LABEL" "$TEMP" "$TEMP_E" "$REALLOC" "$REALLOC_E"
}
DISK_BLOCK=""

[ -b /dev/sda ] && DISK_BLOCK+="$(disk_metrics /dev/sda "SSD")"$'\n'
[ -b /dev/sdb ] && DISK_BLOCK+="$(disk_metrics /dev/sdb "Internal HDD")"$'\n'
[ -b /dev/sdc ] && DISK_BLOCK+="$(disk_metrics /dev/sdc "External HDD")"$'\n'

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

🧮 *CPU*
    • Active CPU Usage (1 min avg): $CPU_ACTIVE% $CPU_E

🗄️ *Disk Health*
$DISK_BLOCK
🕒 *$TS*"

curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
  -d chat_id="$TG_CHAT_ID" \
  -d text="$TG_MSG" \
  -d parse_mode=Markdown \
  -d disable_web_page_preview=true >/dev/null