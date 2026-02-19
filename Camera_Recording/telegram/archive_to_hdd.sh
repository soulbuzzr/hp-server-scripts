#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/Camera_Recording/lib/camera_lib.sh"

log "ARCHIVE" "Hourly archive daemon started"

merge_completed_hour() {
  local camera="$1"
  local ext
  ext=$(file_extension "$camera")

  current_hour=$(date +"%Y-%m/%d/%H")

  find "$OUTPUT_DIR/$camera" -mindepth 3 -maxdepth 3 -type d | while read -r hourdir; do

    rel="${hourdir#$OUTPUT_DIR/$camera/}"

    # ---- Skip current hour ----
    if [ "$rel" = "$current_hour" ]; then
      continue
    fi

    # ---- Skip already merged ----
    if [ -f "$hourdir/.merged" ]; then
      continue
    fi

    # ---- Skip empty dirs ----
    compgen -G "$hourdir/*.${ext}" > /dev/null || continue

    log "MERGE-$camera" "Merging $hourdir"

    mkdir -p "$ARCHIVE_DIR"

    merged_file="$ARCHIVE_DIR/${camera}_$(echo "$rel" | tr '/' '_').${ext}"

    # ----- FFmpeg concat -----
    ffmpeg -f concat -safe 0 \
      -i <(for f in "$hourdir"/*.${ext}; do
              echo "file '$f'"
            done | sort) \
      -c copy \
      "$merged_file"

    if [ $? -eq 0 ]; then
      touch "$hourdir/.merged"

    #   # Remove RAM files after success
    #   rm -f "$hourdir"/*.${ext}
    #   rm -f "$hourdir"/*.uploaded 2>/dev/null || true

      log "MERGE-$camera" "Archived $merged_file"
    else
      log "MERGE-$camera" "Failed merging $hourdir"
    fi

  done
}

while true; do

  merge_completed_hour main &
  merge_completed_hour mini &

  wait

  sleep 20

done
