#!/bin/bash
set -euo pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${TG_BOT_TOKEN:?TG_BOT_TOKEN not set}"
: "${TG_CHAT_ID:?TG_CHAT_ID not set}"
: "${HOST_NAME:?Missing HOST_NAME}"

LOG_FILE="/var/log/system_health.log"

# ================= BASICS =================
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
CPU_INT=${CPU_ACTIVE%.*}
CPU_E=$(cpu_emoji "$CPU_INT")

# ================= DISK METRICS =================
disk_metrics() {
  local DEV="$1"
  local LABEL="$2"

  TEMP=$(smartctl -A "$DEV" 2>/dev/null | awk '$1==194 {print $10+0}')
  REALLOC=$(smartctl -A "$DEV" 2>/dev/null | awk '/Reallocated_Sector_Ct/ {print $NF+0}')

  [ -n "$TEMP" ] || TEMP="N/A"
  [ -n "$REALLOC" ] || REALLOC="0"

  TEMP_E=$(temp_emoji "$TEMP")
  REALLOC_E=$(health_emoji "$REALLOC")

  printf "    💽 *%s*\n        • 🌡️ Temp: %s°C %s\n        • ♻️ Reallocated: %s %s\n" \
    "$LABEL" "$TEMP" "$TEMP_E" "$REALLOC" "$REALLOC_E"
}

# ================= BUILD DISK BLOCK (LIB-DRIVEN) =================
DISK_BLOCK=""

for DEV in $(get_sata_devices); do
  NAME=$(disk_friendly_name "$DEV")
  [ -n "$NAME" ] || continue

  DISK_BLOCK+="$(disk_metrics "$DEV" "$NAME")"$'\n'
done

# ================= FINAL MESSAGE =================
MSG="*$HOST*

⏱️ *Uptime*
    $UPTIME

🧮 *CPU*
    • Active CPU Usage (1 min avg): $CPU_ACTIVE% $CPU_E

🗄️ *Disk Health*
$DISK_BLOCK
🕒 *$TS*"

# ================= LOG =================
echo "$(echo "$MSG" | sed 's/\*//g')" >> "$LOG_FILE"

# ================= TELEGRAM =================
curl -s -X POST "https://api.telegram.org/bot$TG_HOURLY_BOT_TOKEN/sendMessage" \
  -d chat_id="$TG_CHAT_ID" \
  -d text="$MSG" \
  -d parse_mode=Markdown \
  -d disable_web_page_preview=true >/dev/null