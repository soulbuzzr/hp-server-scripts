#!/bin/bash
set -u
set -o pipefail

# ================= RESOLVE HOME DIRECTORY for root user =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

BASE_DIR="$HOME/System_Scripts/System_Health_Monitor"
ENV_FILE="$BASE_DIR/env/system_health_bot.env"
CONF_FILE="$BASE_DIR/conf/system_limits.conf"

# ================= LOAD ENV =================
if [ ! -r "$ENV_FILE" ]; then
  echo "ERROR: Missing env file: $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

: "${TG_BOT_TOKEN:?Missing TG_BOT_TOKEN}"
: "${TG_HOURLY_BOT_TOKEN:?Missing TG_HOURLY_BOT_TOKEN}"
: "${TG_CHAT_ID:?Missing TG_CHAT_ID}"

# ================= LOAD CONFIG =================
if [ ! -r "$CONF_FILE" ]; then
  echo "ERROR: Missing config file: $CONF_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONF_FILE"

# ================= LOGGING =================
LOG_DIR="/var/log/system_health"
LOG_FILE="$LOG_DIR/health.log"

mkdir -p "$LOG_DIR"

log() {
  # Usage: log COMPONENT MESSAGE
  echo "$(date '+%F %T') [$1] $2" >> "$LOG_FILE"
}

# ================= TELEGRAM CORE =================
tg_send_common() {
  local token="$1"
  local message="$2"
  [ -n "$token" ] || return 1

  curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=$message" \
    --data-urlencode "parse_mode=Markdown" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null
}

tg_send()        { tg_send_common "$TG_BOT_TOKEN" "$1"; }
tg_send_hourly() { tg_send_common "$TG_HOURLY_BOT_TOKEN" "$1"; }

# ================= NETWORK =================
internet_up() {
  ping -c1 -W1 8.8.8.8 >/dev/null 2>&1
}

wait_for_network() {
  local tag="${1:-NET}"
  until internet_up; do
    log "$tag" "Waiting for internet..."
    sleep 5
  done
}

startup_notify() {
  local tag="$1"
  local message="$2"
  local sender="${3:-tg_send}"   # default bot
  
  if ! type "$sender" >/dev/null 2>&1; then
    sender="tg_send"
  fi

  log "$tag" "monitor started"
  "$sender" "$message"
}

# ================= CPU TEMPERATURE =================
read_cpu_temp() {
  # Reads CPU temperature in °C (integer) from x86_pkg_temp
  local zone
  for zone in /sys/class/thermal/thermal_zone*; do
    [ -r "$zone/type" ] || continue
    [ -r "$zone/temp" ] || continue
    [ "$(cat "$zone/type" 2>/dev/null)" = "x86_pkg_temp" ] || continue
    awk '{printf "%d\n", $1/1000; exit}' "$zone/temp" 2>/dev/null
    return 0
  done
  return 1
}

# ================= GPU TEMPERATURE =================
read_gpu_temp() {
  # Reads GPU temperature in °C (integer) for Radeon GPU
  local h
  for h in /sys/class/hwmon/hwmon*; do
    [ -r "$h/name" ] || continue
    [ "$(cat "$h/name" 2>/dev/null)" = "radeon" ] || continue
    [ -r "$h/temp1_input" ] || return 1
    awk '{printf "%d\n", $1/1000; exit}' "$h/temp1_input" 2>/dev/null
    return 0
  done
  return 1
}

# ================= DISK DISCOVERY (INTERNAL ONLY) =================
get_sata_devices() {
  smartctl --scan 2>/dev/null | awk '{print $1}' | while read -r dev; do
    # Skip if model is External HDD
    if [ "$(disk_friendly_name "$dev")" = "External HDD" ]; then
      continue
    fi

    echo "$dev"
  done
}

# ================= DISK MODEL NAME =================
disk_model_name() {
  local dev="$1"

  smartctl -i "$dev" 2>/dev/null \
    | awk -F: '/Device Model/ {gsub(/^[ \t]+/,"",$2); print $2; exit}'

}

# ================= DISK FRIENDLY NAME =================
disk_friendly_name() {
  local dev="$1"
  local model

  model=$(disk_model_name "$dev")

  case "$model" in
    *INTEL*SSD*)
      echo "SSD"
      ;;
    *WDC*WD10SPZX*)
      echo "Internal HDD"
      ;;
    *ST500LM000*)
      echo "External HDD"
      ;;
    *)
      echo "${model:-$dev}"
      ;;
  esac
}

# ================= DISK TEMPERATURE =================
disk_temperature() {
  local dev="$1"
  smartctl -A "$dev" 2>/dev/null \
    | awk '$1 == 194 { print $10; exit }'
}

# ================= DISK HEALTH =================
read_realloc() {
  local dev="$1"
  smartctl -A "$dev" 2>/dev/null | awk '/Reallocated_Sector_Ct/ {print $NF+0}'
}

# ================= DISK HEALTH (SSD ONLY) =================
read_wear_value() {
  local dev="$1"
  smartctl -A "$dev" 2>/dev/null | awk '/Media_Wearout_Indicator/ {print $4+0}'
}

# ================= DISK HEALTH (HDD ONLY) =================
read_pending() {
  local dev="$1"
  smartctl -A "$dev" 2>/dev/null | awk '/Current_Pending_Sector/ {print $NF+0}'
}

read_offline() {
  local dev="$1"
  smartctl -A "$dev" 2>/dev/null | awk '/Offline_Uncorrectable/ {print $NF+0}'
}

read_reported() {
  local dev="$1"
  smartctl -A "$dev" 2>/dev/null | awk '/Reported_Uncorrect/ {print $NF+0}'
}

# ================= AVERAGING =================
avg_over_seconds() {
  local seconds="$1" reader="$2"
  local sum=0 count=0

  for _ in $(seq 1 "$seconds"); do
    val="$($reader 2>/dev/null || true)"
    [[ "$val" =~ ^[0-9]+$ ]] && { sum=$((sum + val)); count=$((count + 1)); }
    sleep 1
  done

  (( count == 0 )) && return 1
  awk -v s="$sum" -v c="$count" 'BEGIN{printf "%.2f", s/c}'
}

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

# ================= Mean Average Deviation =================
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
