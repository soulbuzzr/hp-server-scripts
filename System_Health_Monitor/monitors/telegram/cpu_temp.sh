#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/health_lib.sh"

: "${CPU_TEMP_THRESHOLD:?Missing CPU_TEMP_THRESHOLD}"

# ================= BASICS =================
HOST="${HOST_NAME:-🖥️ HP Linux Server}"

# ================= CPU TEMP READER =================
read_cpu_temp() {
  local sum=0 count=0 t
  for z in /sys/class/thermal/thermal_zone6/temp; do
    [ -r "$z" ] || continue
    t=$(cat "$z" 2>/dev/null) || continue
    t=$((t / 1000))
    sum=$((sum + t))
    count=$((count + 1))
  done

  [ "$count" -gt 0 ] && echo $((sum / count))
}

until internet_up; do
  log CPU_TEMP "Waiting for internet before startup notify..."
  sleep 5
done

log CPU_TEMP "Internet is up, starting cpu temp monitor..."
sleep 60

# ================= STARTUP NOTIFY =================
STARTUP_MSG="🌡️ *CPU Temperature Alerts Active*
$HOST
Monitoring: *30-second average CPU temperature*
Threshold: *${CPU_TEMP_THRESHOLD}°C*"

log CPU_TEMP "CPU temperature monitoring started (30-sec avg)"
tg_send "$STARTUP_MSG"

# ================= CONTINUOUS MONITOR =================
while true; do
  SUM=0
  COUNT=0

  # Collect 30 samples, 1 per second
  for _ in $(seq 1 30); do
    TEMP=$(read_cpu_temp)
    [ -n "$TEMP" ] || continue
    SUM=$((SUM + TEMP))
    COUNT=$((COUNT + 1))
    sleep 1
  done

  # No samples → skip this cycle safely
  [ "$COUNT" -eq 0 ] && continue

  # Integer average for comparison
  AVG_TEMP_INT=$((SUM / COUNT))

  # Float average (2 decimals) for display
  AVG_TEMP_FLOAT=$(awk -v s="$SUM" -v c="$COUNT" \
    'BEGIN { printf "%.2f", s / c }')

  log CPU_TEMP "CPU_TEMP_AVG_30SEC=${AVG_TEMP_FLOAT}C"

  if [ "$AVG_TEMP_INT" -ge "$CPU_TEMP_THRESHOLD" ]; then
    ALERT_MSG="🔥 *CPU TEMPERATURE ALERT*
$HOST
30-sec Avg CPU Temp: *${AVG_TEMP_FLOAT}°C*
Threshold: *${CPU_TEMP_THRESHOLD}°C*"

    log CPU_TEMP "CPU TEMP ALERT SENT (${AVG_TEMP_FLOAT}C)"
    tg_send "$ALERT_MSG"
  fi
done
