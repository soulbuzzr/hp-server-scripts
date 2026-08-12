#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/Camera_Recording/lib/camera_lib.sh"

log "CAMERA-ARCHIVE" "Structured archive daemon started"

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

  local cam_root
  cam_root=$(camera_archive_root "$camera") || return 1

  [ -d "$OUTPUT_DIR/$camera" ] || return 0

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
    if   [ "$hour_int" -lt 4 ]; then
        block="Midnight"        # 00:00 - 03:59
    elif [ "$hour_int" -lt 8 ]; then
        block="Early Morning"   # 04:00 - 07:59
    elif [ "$hour_int" -lt 12 ]; then
        block="Morning"         # 08:00 - 11:59
    elif [ "$hour_int" -lt 16 ]; then
        block="Noon"            # 12:00 - 15:59
    elif [ "$hour_int" -lt 20 ]; then
        block="Evening"         # 16:00 - 19:59
    else
        block="Night"           # 20:00 - 23:59
    fi

    archive_path="$ARCHIVE_DIR/$cam_root/$year/$month_name/$day_dir/$block"

    mkdir -p "$archive_path"

    # -------- AM/PM Filename --------
    hour_range=$(format_hour_range "$hour")

    merged_file="$archive_path/${hour_range}.mp4"

    log "MERGE-$camera" "Merging $hourdir -> $merged_file"

    # -------- FFmpeg Concat --------
    # IMPORTANT: under `set -e`, checking `$?` in a separate `if` statement
    # after the command never runs on failure -- the script dies right at
    # the ffmpeg line instead, silently, before the log/failure branch
    # executes. Putting the command directly in the `if` avoids that.
    if ffmpeg -f concat -safe 0 \
      -i <(for f in "$hourdir"/*.${ext}; do
              echo "file '$f'"
           done | sort) \
      -c copy \
      "$merged_file"; then
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
