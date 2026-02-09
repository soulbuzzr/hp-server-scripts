#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${CPU_TEMP_THRESHOLD:?Missing CPU_TEMP_THRESHOLD}"   
: "${HOST_NAME:?Missing HOST_NAME}"

# ================= WAIT FOR NETWORK =================
wait_for_network CPU_TEMP

# ================= STARTUP =================
startup_notify CPU_TEMP "✅ *CPU Temperature Monitor Active*
$HOST_NAME

Monitoring:
• 30-second averaged CPU temperature
Threshold: *${CPU_TEMP_THRESHOLD}°C*"

# ================= MAIN LOOP =================
while true; do
  AVG_TEMP=$(avg_over_seconds 30 read_cpu_temp) || {
    sleep 1
    continue
  }

  AVG_TEMP_INT=${AVG_TEMP%.*}

  log CPU_TEMP "avg_30sec=${AVG_TEMP}C"

  if (( AVG_TEMP_INT >= CPU_TEMP_THRESHOLD )); then
    tg_send "🔥 *CPU TEMPERATURE ALERT*
$HOST_NAME

30-sec Avg CPU Temp: *${AVG_TEMP}°C*
Threshold: *${CPU_TEMP_THRESHOLD}°C*"

    log CPU_TEMP "ALERT SENT (${AVG_TEMP}C)"
  fi

done
