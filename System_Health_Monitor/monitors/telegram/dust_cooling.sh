#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${DUST_CPU_ACTIVE_MAX:?Missing DUST_CPU_ACTIVE_MAX}"
: "${DUST_CPU_TEMP_MIN:?Missing DUST_CPU_TEMP_MIN}"
: "${DUST_CPU_TEMP_MAD_MAX:?Missing DUST_CPU_TEMP_MAD_MAX}"
: "${DUST_DETECT_DURATION:?Missing DUST_DETECT_DURATION}"
: "${HOST_NAME:?Missing HOST_NAME}"

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

# ================= CPU METRICS =================
cpu_sample_60s() {
  local temp_sum=0
  local temp_count=0

  # start mpstat in background
  mpstat 1 60 > /tmp/mpstat.$$ &
  MPSTAT_PID=$!

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

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log DUST "Waiting for internet before startup..."
  sleep 5
done

# ================= STARTUP =================
log DUST "Dust / cooling monitor started"
tg_send "🧹 *Dust / Cooling Monitor Started*
$HOST_NAME

Thresholds:
• CPU active (median) < *${DUST_CPU_ACTIVE_MAX}%*
• Temp (median) > *${DUST_CPU_TEMP_MIN}°C*
• Temp stability (MAD) ≤ *${DUST_CPU_TEMP_MAD_MAX}°C*
• Window: *${DUST_DETECT_DURATION} minutes*"

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

  log DUST "CHECK cpu_med=${CPU_ACTIVE_MED}% temp_med=${CPU_TEMP_MED}C temp_mad=${CPU_TEMP_MAD}C window=${DUST_DETECT_DURATION}m minutes=${DUST_MINUTES}"

  if float_lt "$CPU_ACTIVE_MED" "$DUST_CPU_ACTIVE_MAX" && \
     float_gt "$CPU_TEMP_MED" "$DUST_CPU_TEMP_MIN" && \
     float_lt "$CPU_TEMP_MAD" "$DUST_CPU_TEMP_MAD_MAX"; then
    DUST_MINUTES=$((DUST_MINUTES + 1))
  else
    DUST_MINUTES=0
  fi

  if [ "$DUST_MINUTES" -ge "$DUST_DETECT_DURATION" ]; then
    tg_send "🧹 *POSSIBLE DUST / COOLING ISSUE*
$HOST_NAME

CPU Active (median ${DUST_DETECT_DURATION}m): ${CPU_ACTIVE_MED}%
CPU Temp (median ${DUST_DETECT_DURATION}m): ${CPU_TEMP_MED}°C
CPU Temp Stability (MAD): ${CPU_TEMP_MAD}°C
Duration: ${DUST_DETECT_DURATION} minutes

*Suggestion:*
- Clean fan and vents
- Check airflow"

    log DUST "ALERT SENT (dust/cooling suspected)"
    DUST_MINUTES=0
  fi
done
