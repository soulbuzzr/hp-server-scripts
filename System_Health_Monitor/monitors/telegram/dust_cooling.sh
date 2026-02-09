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

# ================= CPU SAMPLING (≈1 MIN) =================
cpu_sample_60s() {
  local temp_sum=0
  local temp_count=0
  local cpu_active cpu_temp

  mpstat 1 60 > /tmp/mpstat.$$ &
  MPSTAT_PID=$!

  for _ in {1..60}; do
    if cpu_temp=$(read_cpu_temp); then
      temp_sum=$((temp_sum + cpu_temp))
      temp_count=$((temp_count + 1))
    fi
    sleep 1
  done

  wait "$MPSTAT_PID" || true

  cpu_active=$(awk '/Average/ {printf "%.1f", 100 - $NF}' /tmp/mpstat.$$)

  if (( temp_count > 0 )); then
    cpu_temp=$(awk "BEGIN{printf \"%.1f\", $temp_sum / $temp_count}")
  else
    cpu_temp=0
  fi

  rm -f /tmp/mpstat.$$

  echo "$cpu_active $cpu_temp"
}

# ================= WAIT FOR NETWORK =================
wait_for_network DUST

# ================= STARTUP =================
startup_notify DUST "🧹 *Dust / Cooling Monitor Started*
$HOST_NAME

Detection logic:
• CPU activity (median) < *${DUST_CPU_ACTIVE_MAX}%*
• CPU temperature (median) > *${DUST_CPU_TEMP_MIN}°C*
• Temp stability (MAD) ≤ *${DUST_CPU_TEMP_MAD_MAX}°C*
• Duration: *${DUST_DETECT_DURATION} minutes*"

# ================= STATE =================
CPU_ACTIVE_BUF=()
CPU_TEMP_BUF=()
DUST_STREAK=0

# ================= MAIN LOOP =================
while true; do
  read CPU_NOW TEMP_NOW < <(cpu_sample_60s)

  CPU_ACTIVE_BUF+=("$CPU_NOW")
  CPU_TEMP_BUF+=("$TEMP_NOW")

  # ---- rolling window (minutes) ----
  if (( ${#CPU_ACTIVE_BUF[@]} > DUST_DETECT_DURATION )); then
    CPU_ACTIVE_BUF=("${CPU_ACTIVE_BUF[@]:1}")
    CPU_TEMP_BUF=("${CPU_TEMP_BUF[@]:1}")
  fi

  # ---- wait until window full ----
  if (( ${#CPU_ACTIVE_BUF[@]} < DUST_DETECT_DURATION )); then
    continue
  fi

  CPU_ACTIVE_MED=$(median "${CPU_ACTIVE_BUF[@]}")
  CPU_TEMP_MED=$(median "${CPU_TEMP_BUF[@]}")
  CPU_TEMP_MAD=$(mad "${CPU_TEMP_BUF[@]}")

  log DUST "check cpu_med=${CPU_ACTIVE_MED}% temp_med=${CPU_TEMP_MED}C mad=${CPU_TEMP_MAD}C streak=${DUST_STREAK}"

  if float_lt "$CPU_ACTIVE_MED" "$DUST_CPU_ACTIVE_MAX" && \
     float_gt "$CPU_TEMP_MED" "$DUST_CPU_TEMP_MIN" && \
     float_lt "$CPU_TEMP_MAD" "$DUST_CPU_TEMP_MAD_MAX"; then
    DUST_STREAK=$((DUST_STREAK + 1))
  else
    DUST_STREAK=0
  fi

  if (( DUST_STREAK >= DUST_DETECT_DURATION )); then
    tg_send "🧹 *POSSIBLE DUST / COOLING ISSUE*
$HOST_NAME

CPU Active (median ${DUST_DETECT_DURATION}m): *${CPU_ACTIVE_MED}%*
CPU Temp (median ${DUST_DETECT_DURATION}m): *${CPU_TEMP_MED}°C*
CPU Temp Stability (MAD): *${CPU_TEMP_MAD}°C*
Duration: *${DUST_DETECT_DURATION} minutes*

*Suggested actions:*
• Clean fan and vents
• Check airflow
• Inspect thermal paste"

    log DUST "ALERT SENT (dust/cooling suspected)"
    DUST_STREAK=0
  fi
done
