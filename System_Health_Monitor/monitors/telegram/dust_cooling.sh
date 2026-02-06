#!/bin/bash
set -u
set -o pipefail

# ================= REQUIRED ENV =================
: "${TG_BOT_TOKEN:?TG_BOT_TOKEN is not set}"
: "${TG_CHAT_ID:?TG_CHAT_ID is not set}"

HOSTNAME="💻  HP Linux Server"
LOG_FILE="/var/log/system_dust_cooling_alerts.log"

# ================= LOAD CONFIG =================
CONFIG_FILE="/home/hpserver/System_scripts/system_health_monitor.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing config: $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ================= FLOAT HELPERS =================
float_gt() { awk "BEGIN{exit !($1 >  $2)}"; }
float_lt() { awk "BEGIN{exit !($1 <  $2)}"; }

# ================= MEDIAN =================
median() {
  local arr=("$@")
  local n=${#arr[@]}

  IFS=$'\n' sorted=($(sort -n <<<"${arr[*]}"))
  unset IFS

  if (( n % 2 == 1 )); then
    echo "${sorted[$((n/2))]}"
  else
    awk "BEGIN{printf \"%.1f\", (${sorted[$((n/2-1))]} + ${sorted[$((n/2))]}) / 2}"
  fi
}

# ================= MAD =================
mad() {
  local arr=("$@")
  local med
  med=$(median "${arr[@]}")

  local devs=()
  for v in "${arr[@]}"; do
    devs+=("$(awk "BEGIN{print ($v > $med) ? $v-$med : $med-$v}")")
  done

  median "${devs[@]}"
}

# ================= HELPERS =================
log() {
  echo "$(date '+%F %T') $1" >> "$LOG_FILE"
}

tg_send() {
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT_ID" \
    -d text="$1" \
    -d parse_mode=Markdown \
    -d disable_web_page_preview=true >/dev/null
}

# ================= CPU METRICS =================
cpu_sample_60s() {
  local temp_sum=0
  local temp_count=0

  # start mpstat in background
  mpstat 1 60 > /tmp/mpstat.$$ &
  MPSTAT_PID=$!

  # sample temperature once per second (parallel)
  for i in {1..60}; do
    for z in /sys/class/thermal/thermal_zone6/temp; do
      [ -r "$z" ] || continue
      val=$(awk '{print $1/1000}' "$z")
      temp_sum=$(awk "BEGIN{print $temp_sum + $val}")
      temp_count=$((temp_count + 1))
      break
    done
    sleep 1
  done

  wait "$MPSTAT_PID"

  CPU_ACTIVE=$(awk '/Average/ {printf "%.1f",100-$NF}' /tmp/mpstat.$$)
  CPU_TEMP=$(awk "BEGIN{printf \"%.1f\", $temp_sum / $temp_count}")

  rm -f /tmp/mpstat.$$

  echo "$CPU_ACTIVE $CPU_TEMP"
}

# ================= CONNECTIVITY CHECK =================
internet_up() {
  ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
}

until internet_up; do
  log "Waiting for internet before startup notify..."
  sleep 5
done

log "Internet is up, starting dust / cooling monitor..."

# ================= STARTUP =================
log "Dust / cooling monitor started"
sleep 60
tg_send "🧹 *Dust / Cooling Monitor Started*
Host: $HOSTNAME

Thresholds:
• CPU active (median) < ${DUST_CPU_ACTIVE_MAX}%
• Temp (median) > ${DUST_CPU_TEMP_MIN}°C
• Temp stability (MAD) ≤ ${DUST_CPU_TEMP_MAD_MAX}°C
• Window: ${DUST_DETECT_DURATION} minutes"

# ================= MAIN LOOP =================
CPU_ACTIVE_BUF=()
CPU_TEMP_BUF=()
DUST_MINUTES=0

while true; do
  read CPU_NOW TEMP_NOW < <(cpu_sample_60s)

  CPU_ACTIVE_BUF+=("$CPU_NOW")
  CPU_TEMP_BUF+=("$TEMP_NOW")

  # rolling window
  if [ "${#CPU_ACTIVE_BUF[@]}" -gt "$DUST_DETECT_DURATION" ]; then
    CPU_ACTIVE_BUF=("${CPU_ACTIVE_BUF[@]:1}")
    CPU_TEMP_BUF=("${CPU_TEMP_BUF[@]:1}")
  fi

  # wait until window is full
  if [ "${#CPU_ACTIVE_BUF[@]}" -lt "$DUST_DETECT_DURATION" ]; then
    continue
  fi

  CPU_ACTIVE_MED=$(median "${CPU_ACTIVE_BUF[@]}")
  CPU_TEMP_MED=$(median "${CPU_TEMP_BUF[@]}")
  CPU_TEMP_MAD=$(mad "${CPU_TEMP_BUF[@]}")

  log "CHECK cpu_med=${CPU_ACTIVE_MED}% temp_med=${CPU_TEMP_MED}C temp_mad=${CPU_TEMP_MAD}C window=${DUST_DETECT_DURATION}m minutes=${DUST_MINUTES}"

  if float_lt "$CPU_ACTIVE_MED" "$DUST_CPU_ACTIVE_MAX" && \
     float_gt "$CPU_TEMP_MED" "$DUST_CPU_TEMP_MIN" && \
     float_lt "$CPU_TEMP_MAD" "$DUST_CPU_TEMP_MAD_MAX"; then
    DUST_MINUTES=$((DUST_MINUTES + 1))
  else
    DUST_MINUTES=0
  fi

  if [ "$DUST_MINUTES" -ge "$DUST_DETECT_DURATION" ]; then
    MSG="🧹 *POSSIBLE DUST / COOLING ISSUE*
Host: $HOSTNAME

CPU Active (median ${DUST_DETECT_DURATION}m): ${CPU_ACTIVE_MED}%
CPU Temp (median ${DUST_DETECT_DURATION}m): ${CPU_TEMP_MED}°C
CPU Temp Stability (MAD): ${CPU_TEMP_MAD}°C
Duration: ${DUST_DETECT_DURATION} minutes

*Suggestion:*
- Clean fan and vents
- Check airflow"

    log "$MSG"
    tg_send "$MSG"
    DUST_MINUTES=0
  fi
done
