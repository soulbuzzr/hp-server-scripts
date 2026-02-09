#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${CPU_ACTIVE_THRESHOLD:?Missing CPU_ACTIVE_THRESHOLD}"  
: "${HOST_NAME:?Missing HOST_NAME}"

# ================= WAIT FOR NETWORK =================
wait_for_network CPU

# ================= STARTUP =================
startup_notify CPU "✅ *CPU Load Monitor Active*
$HOST_NAME

Monitoring:
• 1-minute average CPU usage
Threshold: *${CPU_ACTIVE_THRESHOLD}%*"

# ================= MAIN LOOP =================
while true; do
    CPU_AVG=$(mpstat 1 60 | awk '/Average/ {printf "%.2f",100-$NF}')
    CPU_INT=${CPU_AVG%.*}

    log CPU "avg_1min=${CPU_AVG}%"

    if (( CPU_INT >= CPU_ACTIVE_THRESHOLD )); then
      tg_send "🚨 *CPU ALERT*
$HOST_NAME

1-min Avg CPU Usage: *${CPU_AVG}%*
Threshold: *${CPU_ACTIVE_THRESHOLD}%*"

      log CPU "ALERT SENT (${CPU_AVG}%)"
    fi
done
