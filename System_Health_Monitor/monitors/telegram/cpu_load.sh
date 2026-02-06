#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/health_lib.sh"

: "${CPU_ACTIVE_THRESHOLD:?Missing CPU_ACTIVE_THRESHOLD}"

# ================= BASICS =================
HOST="${HOST_NAME:-🖥️ HP Linux Server}"

until internet_up; do
  log CPU "Waiting for internet before startup notify..."
  sleep 5
done

log CPU "Internet is up, starting cpu load monitor..."
sleep 60

# ================= STARTUP NOTIFY =================
STARTUP_MSG="✅ *CPU Alerts Active*
$HOST
Monitoring: *1-minute average CPU usage*
Threshold: *${CPU_ACTIVE_THRESHOLD}%*"

log CPU "CPU monitoring started (1-min avg)"
tg_send "$STARTUP_MSG"

# ================= CONTINUOUS MONITOR =================
while true; do
  # mpstat blocks for 60 seconds → this IS the timer
  CPU_AVG=$(mpstat 1 60 | awk '/Average/ {printf "%.2f",100-$NF}')
  CPU_INT=${CPU_AVG%.*}

  log CPU "CPU_AVG_1MIN=${CPU_AVG}%"

  if [ "$CPU_INT" -ge "$CPU_ACTIVE_THRESHOLD" ]; then
    ALERT_MSG="🚨 *CPU ALERT*
$HOST
1-min Avg CPU Usage: *${CPU_AVG}%*
Threshold: *${CPU_ACTIVE_THRESHOLD}%*"

    log CPU "CPU ALERT SENT (${CPU_AVG}%)"
    tg_send "$ALERT_MSG"
  fi
done
