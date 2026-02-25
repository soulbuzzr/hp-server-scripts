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

  curl -s -X POST "${TG_API_BASE}${token}/${method}" "$@"
}

# ================= TELEGRAM STATUS =================
cam_status_send() {
  cam_tg_api "$TG_CAMERA_STATUS_BOT_TOKEN" sendMessage \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=$1" \
    --data-urlencode "parse_mode=Markdown" \
    --data-urlencode "disable_web_page_preview=true" \
    >/dev/null 2>&1
}

# ================= TELEGRAM FILE =================
cam_tg_send_file_common() {
  local token="$1"
  local file="$2"
  local caption="$3"

  cam_tg_api "$token" sendDocument \
    -F "chat_id=$TG_CHAT_ID" \
    -F "caption=$caption" \
    -F document=@"$file"
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
  local target_mac ip attempt

  target_mac=$(echo "$1" | tr '[:upper:]' '[:lower:]')

  # ----- Try arp-scan 5 times -----
  for attempt in {1..5}; do
    ip=$(arp-scan "$SUBNET" 2>/dev/null \
        | awk -v m="$target_mac" 'tolower($2)==m {print $1; exit}')

    if [ -n "$ip" ]; then
      log "DISCOVERY" "Found $target_mac via arp-scan ($ip)"
      echo "$ip"
      return 0
    fi
    sleep 1
  done

  log "DISCOVERY" "ARP failed for $target_mac, trying nmap"

  # ---- Fallback: nmap scan ----
  nmap -sn "$SUBNET" >/dev/null 2>&1

  ip=$(arp -an 2>/dev/null \
      | awk -v m="$target_mac" '
        tolower($4)==m {
          gsub(/[()]/,"",$2);
          print $2;
          exit
        }')

  if [ -n "$ip" ]; then
    log "DISCOVERY" "Found $target_mac via nmap ($ip)"
    echo "$ip"
    return 0
  fi

  log "DISCOVERY" "Failed to find $target_mac"
  return 1
}

build_rtsp_url() {
  local cam="$1"
  local mac ip

  case "$cam" in
    main) mac="$MAIN_CAMERA_MAC" ;;
    mini) mac="$MINI_CAMERA_MAC" ;;
    *) log "LIB" "Unknown camera type: $cam"; return 1 ;;
  esac

  ip=$(get_ip_from_mac "$mac") || return 1

  echo "rtsp://${ip}:${RTSP_PORT}${CAMERA_RTSP_PATH}"
}

# ================= FILE EXTENSION =================
file_extension() {
  case "$1" in
    main) echo "$MAIN_CAMERA_FILE_EXTENSION" ;;
    mini) echo "$MINI_CAMERA_FILE_EXTENSION" ;;
    *) return 1 ;;
  esac
}

# ================= CAMERA RECORD (COMMON) =================
cam_record_common() {
  local camera="$1"

  rtsp_url=$(build_rtsp_url "$camera") || {
    cam_status_send "⚠️ $camera camera not reachable"
    return 1
  }

  ext=$(file_extension "$camera") || return 1
  mkdir -p "$OUTPUT_DIR/$camera"

  log "REC-$camera" "Starting continuous segmented recording"

  # ----- Codec selection -----
  if [ "$camera" = "main" ]; then
    codec_opts=(-c copy)
  else
    codec_opts=(-c:v copy -c:a aac -b:a 64k)
  fi

  # ----- MP4 specific flags -----
  if [ "$ext" = "mp4" ]; then
    movflags_opts=(-movflags +faststart)
  else
    movflags_opts=()
  fi

  # ----- Start FFmpeg -----
  ffmpeg -nostdin -loglevel error \
    -rtsp_transport tcp \
    -timeout "$RTSP_TIMEOUT" \
    -fflags +genpts \
    -use_wallclock_as_timestamps 1 \
    -i "$rtsp_url" \
    "${codec_opts[@]}" \
    -f segment \
    -segment_time "$SEGMENT_DURATION" \
    -segment_atclocktime 1 \
    -reset_timestamps 1 \
    -strftime 1 \
    "${movflags_opts[@]}" \
    "$OUTPUT_DIR/$camera/%Y-%m/%d/%H/${camera}_%Y-%m-%d_%H-%M-%S.${ext}"

  if [ $? -ne 0 ]; then
    log "REC-$camera" "FFmpeg stopped unexpectedly"
    cam_status_send "❌ $camera camera recorder stopped"
    return 1
  fi

}

# ================= CAPTION HELPER =================
format_caption() {
  local file="$1"

  # Extract datetime from filename
  dt=$(basename "$file" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9-]\{8\}')
  dt="${dt//_/ }"
  dt="${dt//-/ }"

  read -r Y M D H Min S <<< "$dt"

  day_suffix() {
    case "$1" in
      1|21|31) echo "st" ;;
      2|22) echo "nd" ;;
      3|23) echo "rd" ;;
      *) echo "th" ;;
    esac
  }

  suffix=$(day_suffix "$D")
  month=$(date -d "$Y-$M-$D" +"%b")

  echo "${D}${suffix} ${month} ${Y} ${H}:${Min}"
}