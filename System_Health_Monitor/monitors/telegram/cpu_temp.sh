#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${CPU_TEMP_THRESHOLD:?Missing CPU_TEMP_THRESHOLD}"
: "${HOST_NAME:?Missing HOST_NAME}"

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log CPU_TEMP "Waiting for internet..."
  sleep 5
done

# ================= STARTUP NOTIFY =================
STARTUP_MSG="✅ *CPU Temperature Monitor Active*
$HOST_NAME
Monitoring: *30-second averaged CPU temperature*
Threshold: *${CPU_TEMP_THRESHOLD}°C*"

log CPU_TEMP "CPU temperature monitor started (30s avg, threshold=${CPU_TEMP_THRESHOLD}C)"
tg_send "$STARTUP_MSG"

# ================= TEMP READER =================
read_cpu_temp() {
  for z in /sys/class/thermal/thermal_zone6/temp; do
    [ -r "$z" ] || continue
    awk '{printf "%d",$1/1000; exit}' "$z"
  done
}

# ================= CONTINUOUS MONITOR =================
while true; do
  SUM=0
  COUNT=0

  # Collect 30 samples (1 per second)
  for _ in $(seq 1 30); do
    TEMP=$(read_cpu_temp || echo "")
    if [ -n "$TEMP" ]; then
      SUM=$((SUM + TEMP))
      COUNT=$((COUNT + 1))
    fi
    sleep 1
  done

  # No samples → skip safely
  [ "$COUNT" -eq 0 ] && continue

  # Integer average (for comparison)
  AVG_TEMP_INT=$((SUM / COUNT))

  # Float average (for display)
  AVG_TEMP_FLOAT=$(awk -v s="$SUM" -v c="$COUNT" \
    'BEGIN { printf "%.2f", s / c }')

  log CPU_TEMP "CPU_TEMP_AVG_30SEC=${AVG_TEMP_FLOAT}C"

  if (( AVG_TEMP_INT >= CPU_TEMP_THRESHOLD )); then
    ALERT_MSG="🔥 *CPU TEMPERATURE ALERT*
$HOST_NAME
30-sec Avg CPU Temp: *${AVG_TEMP_FLOAT}°C*
Threshold: *${CPU_TEMP_THRESHOLD}°C*"

    log CPU_TEMP "ALERT SENT (${AVG_TEMP_FLOAT}C)"
    tg_send "$ALERT_MSG"
  fi
done
