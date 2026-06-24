#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME DIRECTORY for root user =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${TG_HOURLY_BOT_TOKEN:?Missing TG_HOURLY_BOT_TOKEN}"
: "${TG_CHAT_ID:?Missing TG_CHAT_ID}"
: "${HOST_NAME:?Missing HOST_NAME}"

# ================= WAIT FOR NETWORK =================
wait_for_network HOURLY

# ================= BASICS =================
TS="$(date '+%Y-%m-%d %H:%M:%S')"
UPTIME="$(uptime -p | sed 's/^up //')"

# ================= EMOJI HELPERS =================
cpu_emoji() {
  if [ "$1" -lt 20 ]; then echo "🟢"
  elif [ "$1" -lt 60 ]; then echo "🟡"
  else echo "🔴"; fi
}

temp_emoji() {
  if [ "$1" -lt 45 ]; then echo "🟢"
  elif [ "$1" -lt 65 ]; then echo "🟡"
  else echo "🔴"; fi
}

health_emoji() {
  if [ "$1" -eq 0 ]; then echo "🟢"
  elif [ "$1" -lt 10 ]; then echo "🟡"
  else echo "🔴"; fi
}

# ================= CPU METRICS =================
CPU_ACTIVE=$(mpstat 1 60 | awk '/Average/ {printf "%.2f",100-$NF}')
CPU_INT=${CPU_ACTIVE%.*}
CPU_E=$(cpu_emoji "$CPU_INT")

CPU_BLOCK="🧮 *CPU*
    • Active CPU Usage (1 min avg): *$CPU_ACTIVE%* $CPU_E

"

# ================= DISK BLOCK (SATA) =================
for DEV in $(get_sata_devices); do
  NAME="$(disk_friendly_name "$DEV")"

  TEMP="$(disk_temperature "$DEV" || true)"
  [[ "$TEMP" =~ ^[0-9]+$ ]] || TEMP="?"

  # SSD
  if WEAR="$(read_wear_value "$DEV" 2>/dev/null)"; then
    REALLOC="$(read_realloc "$DEV")"

    read BASE_REALLOC _ _ _ BASE_WEAR \
      <<< "$(get_disk_Thresholds "$NAME")"

    DISK_BLOCK+="📀 *$NAME*
    • 🌡 Temp: *${TEMP}°C*
    • ♻ Reallocated: *${REALLOC}/${BASE_REALLOC}*
    • ❤️ Life Remaining: *${WEAR}%* 

"

  # HDD
  else
    REALLOC="$(read_realloc "$DEV")"
    PENDING="$(read_pending "$DEV")"
    OFFLINE="$(read_offline "$DEV")"
    REPORTED="$(read_reported "$DEV")"

    read BASE_REALLOC BASE_PENDING BASE_OFFLINE BASE_REPORTED _ \
      <<< "$(get_disk_Thresholds "$NAME")"

    DISK_BLOCK+="📀 *$NAME*
    • 🌡 Temp: *${TEMP}°C*
    • ♻ Reallocated: *${REALLOC}/${BASE_REALLOC}*
    • ⏳ Pending: *${PENDING}/${BASE_PENDING}*
    • ❌ Offline: *${OFFLINE}/${BASE_OFFLINE}*
    • ⚠ Reported: *${REPORTED}/${BASE_REPORTED}*

"
  fi
done

# ================= GPU BLOCK (RADEON, OPTIONAL) =================
GPU_TEMP="$(read_gpu_temp || true)"
if [[ "$GPU_TEMP" =~ ^[0-9]+$ ]]; then
  GPU_E=$(temp_emoji "$GPU_TEMP")
  GPU_BLOCK="🎮 *GPU*
• Radeon Temp: *${GPU_TEMP}°C* ${GPU_E}

"
fi

# ================= MEMORY BLOCK =================
read RAM_USED RAM_PCT RAM_AVAIL RAM_TOTAL <<< \
$(free -h | awk '/Mem:/ {printf "%s %.0f %s %s",$3,$3/$2*100,$7,$2}')

SWAP_AVAIL="$(free -h | awk '/Swap:/ {print $4}')"

MEM_BLOCK="🧠 *Memory*
• Used: *${RAM_USED}* (${RAM_PCT}%)
• Available: ${RAM_AVAIL}
• Total: ${RAM_TOTAL}

💾 *Swap*
• Available: ${SWAP_AVAIL}"

# ================= FINAL MESSAGE =================
MSG="*${HOST_NAME}*

⏱ *Uptime*
${UPTIME}

${CPU_BLOCK}${DISK_BLOCK}${GPU_BLOCK}${MEM_BLOCK}

🕒 *${TS}*"

# ================= SEND =================
log HOURLY_STATS "sending hourly system health report"
tg_send_hourly "$MSG"
