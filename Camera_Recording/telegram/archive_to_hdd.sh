#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/Camera_Recording/lib/camera_lib.sh"

log "CAMERA-ARCHIVE" "Structured archive daemon started"

# ================= DAY SUFFIX =================
day_suffix() {
  case "$1" in
    1|21|31) echo "st" ;;
    2|22) echo "nd" ;;
    3|23) echo "rd" ;;
    *) echo "th" ;;
  esac
}

# ================= FORMAT HOUR RANGE =================
format_hour_range() {
    local hour="$1"

    start_fmt=$(date -d "1970-01-01 ${hour}:00:00" +"%I %p")
    next_hour=$(( (10#$hour + 1) % 24 ))
    next_hour_pad=$(printf "%02d" "$next_hour")
    end_fmt=$(date -d "1970-01-01 ${next_hour_pad}:00:00" +"%I %p")

    echo "${start_fmt} - ${end_fmt}"
}

# ================= MERGE FUNCTION =================
merge_completed_hour() {

  local camera="$1"
  local ext
  ext=$(file_extension "$camera")

  # Camera folder mapping
  if [ "$camera" = "main" ]; then
      cam_root="Main-camera"
  else
      cam_root="Mini-camera"
  fi

  current_hour=$(date +"%Y-%m/%d/%H")

  find "$OUTPUT_DIR/$camera" -mindepth 3 -maxdepth 3 -type d | while read -r hourdir; do

    rel="${hourdir#$OUTPUT_DIR/$camera/}"

    # Skip current hour
    if [ "$rel" = "$current_hour" ]; then
      continue
    fi

    # Skip if already merged
    if [ -f "$hourdir/.merged" ]; then
      continue
    fi

    # Skip empty folders
    compgen -G "$hourdir/*.${ext}" > /dev/null || continue

    # -------- Extract Date Parts --------
    year_month=$(echo "$rel" | cut -d'/' -f1)
    day=$(echo "$rel" | cut -d'/' -f2)
    hour=$(echo "$rel" | cut -d'/' -f3)

    year=$(echo "$year_month" | cut -d'-' -f1)
    month_num=$(echo "$year_month" | cut -d'-' -f2)

    month_name=$(date -d "$year-$month_num-01" +"%B")

    suffix=$(day_suffix "$day")
    day_dir="${day}${suffix}"

    hour_int=$((10#$hour))

    # -------- Time Blocks --------
    if   [ "$hour_int" -le 3 ]; then
        block="Midnight"
    elif [ "$hour_int" -le 6 ]; then
        block="Early Morning"
    elif [ "$hour_int" -le 12 ]; then
        block="Morning"
    elif [ "$hour_int" -le 15 ]; then
        block="Noon"
    elif [ "$hour_int" -le 18 ]; then
        block="Evening"
    else
        block="Night"
    fi

    archive_path="$ARCHIVE_DIR/$cam_root/$year/$month_name/$day_dir/$block"

    mkdir -p "$archive_path"

    # -------- AM/PM Filename --------
    hour_range=$(format_hour_range "$hour")

    merged_file="$archive_path/${hour_range}.mp4"

    log "MERGE-$camera" "Merging $hourdir -> $merged_file"

    # -------- FFmpeg Concat --------
    ffmpeg -f concat -safe 0 \
      -i <(for f in "$hourdir"/*.${ext}; do
              echo "file '$f'"
           done | sort) \
      -c copy \
      "$merged_file"

    if [ $? -eq 0 ]; then
      touch "$hourdir/.merged"
      log "MERGE-$camera" "Archived successfully"
    else
      log "MERGE-$camera" "Failed merging $hourdir"
    fi

  done
}

# ================= MAIN LOOP =================
while true; do

  merge_completed_hour main &
  merge_completed_hour mini &

  wait

  sleep 60
  
done
