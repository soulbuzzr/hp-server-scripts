#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/health_lib.sh"

: "${GPU_TEMP_THRESHOLD:?Missing GPU_TEMP_THRESHOLD}"

# ================= BASICS =================
HOST="${HOST_NAME:-🖥️ HP Linux Server}"

GPU_TEMP_PATH="/sys/class/hwmon/hwmon4/temp1_input"

# ================= GPU TEMP READER =================
read_gpu_temp() {
  [ -r "$GPU_TEMP_PATH" ] || return
  echo $(( $(cat "$GPU_TEMP_PATH") / 1000 ))
}

until internet_up; do
  log GPU_TEMP "Waiting for internet before startup notify..."
  sleep 5
done

log GPU_TEMP "Internet is up, starting gpu temp monitor..."
sleep 60

# ================= STARTUP NOTIFY =================
START_TEMP=$(read_gpu_temp || echo "N/A")

STARTUP_MSG="🎮 *GPU Temperature Alerts Active*
$HOST
Current GPU Temp: *${START_TEMP}°C*
Monitoring: *30-second average GPU temperature*
Threshold: *${GPU_TEMP_THRESHOLD}°C*"

log GPU_TEMP "GPU temperature monitoring started (30-sec avg)"
tg_send "$STARTUP_MSG"

# ================= CONTINUOUS MONITOR =================
while true; do
  SUM=0
  COUNT=0

  # Collect 30 samples, 1 per second
  for _ in $(seq 1 30); do
    TEMP=$(read_gpu_temp)
    [ -n "$TEMP" ] || continue
    SUM=$((SUM + TEMP))
    COUNT=$((COUNT + 1))
    sleep 1
  done

  # No samples → skip safely
  [ "$COUNT" -eq 0 ] && continue

  # Integer average (logic)
  AVG_TEMP_INT=$((SUM / COUNT))

  # Float average (display)
  AVG_TEMP_FLOAT=$(awk -v s="$SUM" -v c="$COUNT" \
    'BEGIN { printf "%.2f", s / c }')

  log GPU_TEMP "GPU_TEMP_AVG_30SEC=${AVG_TEMP_FLOAT}C"

  if [ "$AVG_TEMP_INT" -ge "$GPU_TEMP_THRESHOLD" ]; then
    ALERT_MSG="🔥 *GPU TEMPERATURE ALERT*
$HOST
30-sec Avg GPU Temp: *${AVG_TEMP_FLOAT}°C*
Threshold: *${GPU_TEMP_THRESHOLD}°C*"

    log GPU_TEMP "GPU TEMP ALERT SENT (${AVG_TEMP_FLOAT}C)"
    tg_send "$ALERT_MSG"
  fi
done
