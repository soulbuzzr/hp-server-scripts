#!/bin/bash
set -u
set -o pipefail

# ================= RESOLVE HOME DIRECTORY =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

BASE_DIR="$HOME/System_Scripts/Camera_Recording"
CONF_FILE="$BASE_DIR/conf/camera.conf"
ENV_FILE="$BASE_DIR/env/camera_bot.env"

# ================= LOAD CONFIG =================
if [ ! -r "$CONF_FILE" ]; then
  echo "ERROR: Missing config file: $CONF_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONF_FILE"

# ================= LOAD ENV =================
if [ ! -r "$ENV_FILE" ]; then
  echo "ERROR: Missing env file: $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

: "${TG_CHAT_ID:?Missing TG_CHAT_ID}"
: "${TG_MAIN_CAMERA_TOKEN:?Missing TG_MAIN_CAMERA_TOKEN}"
: "${TG_MINI_CAMERA_TOKEN:?Missing TG_MINI_CAMERA_TOKEN}"
: "${TG_CAMERA_STATUS_BOT_TOKEN:?Missing TG_CAMERA_STATUS_BOT_TOKEN}"

# ================= LOGGING =================
LOG_DIR="/var/log/camera_recording"
LOG_FILE="$LOG_DIR/camera.log"
mkdir -p "$LOG_DIR"

log() {
  echo "$(date '+%F %T') [$1] $2" >> "$LOG_FILE"
}

# ================= TELEGRAM CORE =================
TG_API_BASE="https://api.telegram.org/bot"

cam_tg_api() {
  local token="$1"
  local method="$2"
  shift 2
  [ -n "$token" ] || return 1

  curl -s -X POST "${TG_API_BASE}${token}/${method}" "$@" >/dev/null
}

# ================= TELEGRAM MESSAGE (STATUS ONLY) =================
cam_status_send() {
  cam_tg_api "$TG_CAMERA_STATUS_BOT_TOKEN" sendMessage \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=$1" \
    --data-urlencode "parse_mode=Markdown" \
    --data-urlencode "disable_web_page_preview=true"
}

# ================= TELEGRAM FILE =================
cam_tg_send_file_common() {
  local token="$1"
  local file="$2"
  local caption="$3"
  [ -n "$token" ] || return 1

  curl -s -X POST "${TG_API_BASE}${token}/sendDocument" \
    -F "chat_id=$TG_CHAT_ID" \
    -F "caption=$caption" \
    -F document=@"$file" >/dev/null
}

cam_main_send_file() { cam_tg_send_file_common "$TG_MAIN_CAMERA_TOKEN" "$1" "$2"; }
cam_mini_send_file() { cam_tg_send_file_common "$TG_MINI_CAMERA_TOKEN" "$1" "$2"; }

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

# ================= CAMERA DISCOVERY =================
get_ip_from_mac() {
  local mac
  mac=$(echo "$1" | tr '[:upper:]' '[:lower:]')

  arp-scan "$SUBNET" 2>/dev/null \
    | awk -v m="$mac" 'tolower($2)==m {print $1; exit}'
}

build_rtsp_url() {
  local cam="$1"
  local mac ip

  case "$cam" in
    main) mac="$MAIN_CAMERA_MAC" ;;
    mini) mac="$MINI_CAMERA_MAC" ;;
    *)
      log "LIB" "Unknown camera type: $cam"
      return 1
      ;;
  esac

  ip=$(get_ip_from_mac "$mac")

  if [ -z "$ip" ]; then
    log "LIB" "Camera $cam not found"
    return 1
  fi

  echo "rtsp://${ip}:${RTSP_PORT}${CAMERA_RTSP_PATH}"
}

file_extension() {
  case "$1" in
    main) echo "$MAIN_CAMERA_CONTAINER" ;;
    mini) echo "$MINI_CAMERA_CONTAINER" ;;
    *) return 1 ;;
  esac
}

# ================= TIME ALIGNMENT =================
is_segment_boundary() {
  local min sec
  min=$(date +%M)
  sec=$(date +%S)

  [ "$sec" -eq 0 ] && [ $((10#$min % 5)) -eq 0 ]
}

# ================= CAMERA RECORD (COMMON) =================
cam_record_common() {
  local camera="$1"

  local rtsp_url ext file

  rtsp_url=$(build_rtsp_url "$camera") || return 1
  ext=$(file_extension "$camera") || return 1

  mkdir -p "$OUTPUT_DIR/$camera"

  file="$OUTPUT_DIR/$camera/${camera}_$(date +%Y-%m-%d_%H-%M-%S).$ext"

  log "REC-$camera" "Recording $file"

  ffmpeg -nostdin -loglevel error \
    -rtsp_transport tcp \
    "$@" \
    -fflags +genpts -use_wallclock_as_timestamps 1 \
    -i "$rtsp_url" \
    -t "$SEGMENT_DURATION" \
    "$file"
}

# ================= MAIN CAMERA RECORD =================
cam_main_record() {
  cam_record_common main \ 
    -c copy
}

# ================= MINI CAMERA RECORD =================
cam_mini_record() {
  cam_record_common mini \
    -c:v copy -c:a aac -b:a 64k
}
