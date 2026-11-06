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

# ========== LOAD TELEGRAM ENCRYPTION PASSWORD =================
source /etc/telegram-upload/credentials/encryption-password

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
LOG_DIR="$HOME/Ramdisk/.logs"
LOG_FILE="$LOG_DIR/camera.log"
mkdir -p "$LOG_DIR"

log() {
  echo "$(date '+%F %T') [$1] $2" >> "$LOG_FILE"
}

# ================= DAY SUFFIX (shared) =================
day_suffix() {
  # Strip any leading zero so "01", "02", "03" match the case patterns
  # the same way "1", "2", "3" do (base-10 forced to avoid octal issues
  # with "08"/"09").
  local d=$((10#$1))
  case "$d" in
    1|21|31) echo "st" ;;
    2|22) echo "nd" ;;
    3|23) echo "rd" ;;
    *) echo "th" ;;
  esac
}

# ================= CAMERA ATTRIBUTE MAP (shared) =================
# Centralizes the main/mini -> folder name / sender-function dispatch that
# was previously duplicated with inline if/else blocks in multiple scripts.
camera_archive_root() {
  case "$1" in
    main) echo "Main-camera" ;;
    mini) echo "Mini-camera" ;;
    *) log "LIB" "Unknown camera type: $1"; return 1 ;;
  esac
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
    >/dev/null 2>&1 || true
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

# Dispatcher so callers don't need their own main/mini if/else.
cam_send_file() {
  local camera="$1" file="$2" caption="$3"
  case "$camera" in
    main) cam_main_send_file "$file" "$caption" ;;
    mini) cam_mini_send_file "$file" "$caption" ;;
    *) log "LIB" "Unknown camera type: $camera"; return 1 ;;
  esac
}

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

# ----- DISCOVER RTSP DEVICES USING NMAP -----
discover_rtsp_devices() {
    local output

    log "DISCOVERY" "Scanning $SUBNET for RTSP port $RTSP_PORT"

    output=$(nmap -n -sT -p "$RTSP_PORT" --open -oG - "$SUBNET" 2>/dev/null) || {
        log "DISCOVERY" "Nmap scan failed"
        return 1
    }

    awk -v port="$RTSP_PORT" '
        $1 == "Host:" {
            for (i = 1; i <= NF; i++) {
                if ($i == "Ports:") {
                    for (j = i + 1; j <= NF; j++) {
                        count = split($j, entries, ",")
                        for (k = 1; k <= count; k++) {
                            if (index(entries[k], port "/open/tcp/") == 1) {
                                print $2
                                next
                            }
                        }
                    }
                }
            }
        }
    ' <<< "$output" | sort -Vu
}

# ----- IDENTIFY CAMERA STREAM -----
identify_camera_stream() {
  local ip="$1"
  local camera="$2"
  local stream_info

  stream_info=$(ffprobe -v error \
    -rtsp_transport tcp \
    -timeout "$RTSP_TIMEOUT" \
    -show_entries stream=codec_type,codec_name,width,height \
    -of json \
    "rtsp://${ip}:${RTSP_PORT}${CAMERA_RTSP_PATH}" 2>/dev/null) || return 1

  case "$camera" in
    main)
      jq -e '
        [.streams[] |
          select(
            .codec_type == "video" and
            .codec_name == "hevc" and
            .width == 2304 and
            .height == 2592
          )
        ] | length == 1
      ' <<< "$stream_info" >/dev/null
      ;;

    mini)
      jq -e '
        [.streams[] |
          select(
            .codec_type == "video" and
            .codec_name == "h264" and
            .width == 1280 and
            .height == 720
          )
        ] | length == 1
      ' <<< "$stream_info" >/dev/null
      ;;

    *)
      return 1
      ;;
  esac
}


# ----- GET CAMERA IP BY STREAM SIGNATURE -----
get_ip_from_camera_type() {
  local camera="$1"
  local ip
  local -a candidates=()
  local -a matches=()

  local candidate_output

  candidate_output=$(discover_rtsp_devices) || return 1

  if [[ -n "$candidate_output" ]]; then
      mapfile -t candidates <<< "$candidate_output"
  fi
    if ((${#candidates[@]} == 0)); then
      log "DISCOVERY" "No RTSP devices found"
      return 1
    fi

  log "DISCOVERY" "RTSP candidates: ${candidates[*]}"

  for ip in "${candidates[@]}"; do
    if identify_camera_stream "$ip" "$camera"; then
      matches+=("$ip")
      log "DISCOVERY" "$camera camera identified at $ip"
    fi
  done

  if ((${#matches[@]} == 1)); then
    echo "${matches[0]}"
    return 0
  fi

  if ((${#matches[@]} > 1)); then
    log "DISCOVERY" "Multiple $camera camera matches: ${matches[*]}"
  else
    log "DISCOVERY" "No matching stream found for $camera"
  fi

  return 1
}


# ----- BUILD RTSP URL -----
build_rtsp_url() {
  local cam="$1"
  local ip

  case "$cam" in
    main|mini) ;;
    *)
      log "LIB" "Unknown camera type: $cam"
      return 1
      ;;
  esac

  ip=$(get_ip_from_camera_type "$cam") || return 1

  printf 'rtsp://%s:%s%s\n' \
    "$ip" "$RTSP_PORT" "$CAMERA_RTSP_PATH"
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

# ================= RECORDER LOOP (shared) =================
# Both main_camera_recorder.sh and mini_camera_recorder.sh reduce to a
# single call into this function.
run_camera_recorder() {
  local camera="$1"       # main | mini
  local log_tag="$2"      # e.g. MAIN_CAMERA
  local emoji="${3:-🎥}"

  wait_for_network "$log_tag"

  log "$log_tag" "Starting recording...."
  cam_status_send "${emoji} ${camera^} camera recording started at $(date '+%F %T')"

  while true; do
    cam_record_common "$camera"
    cam_status_send "⚠ ${camera^} camera restarting recording"
    sleep 5
  done
}

# ================= CAPTION HELPER =================
format_caption() {
  local file="$1"

  # Extract datetime from filename
  dt=$(basename "$file" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9-]\{8\}')
  dt="${dt//_/ }"
  dt="${dt//-/ }"

  read -r Y M D H Min S <<< "$dt"

  suffix=$(day_suffix "$D")
  month=$(date -d "$Y-$M-$D" +"%b")

  echo "${D}${suffix} ${month} ${Y} ${H}:${Min}"
}