#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${CPU_ACTIVE_THRESHOLD:?Missing CPU_ACTIVE_THRESHOLD}"
: "${HOST_NAME:?Missing HOST_NAME}"

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log CPU "Waiting for internet..."
  sleep 5
done

# ================= STARTUP NOTIFY =================
STARTUP_MSG="✅ *CPU Load Monitor Active*
$HOST_NAME
Monitoring: *1-minute average CPU usage*
Threshold: *${CPU_ACTIVE_THRESHOLD}%*"

log CPU "CPU monitoring started (1-min avg, threshold=${CPU_ACTIVE_THRESHOLD}%)"
tg_send "$STARTUP_MSG"

# ================= MONITOR LOOP =================
while true; do
  # mpstat blocks for 60s → acts as timer
  CPU_AVG=$(mpstat 1 60 | awk '/Average/ {printf "%.2f",100-$NF}')
  CPU_INT=${CPU_AVG%.*}

  log CPU "CPU_AVG_1MIN=${CPU_AVG}%"

  if (( CPU_INT >= CPU_ACTIVE_THRESHOLD )); then
    ALERT_MSG="🚨 *CPU ALERT*
$HOST_NAME
1-min Avg CPU Usage: *${CPU_AVG}%*
Threshold: *${CPU_ACTIVE_THRESHOLD}%*"

    log CPU "ALERT SENT (${CPU_AVG}%)"
    tg_send "$ALERT_MSG"
  fi
done
