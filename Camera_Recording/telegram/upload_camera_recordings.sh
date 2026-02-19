#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/Camera_Recording/lib/camera_lib.sh"

upload_new_files() {
  local camera="$1"
  local ext
  ext=$(file_extension "$camera")

  while IFS= read -r file; do
    marker="${file}.uploaded"

    # Skip if already uploaded
    [ -f "$marker" ] && continue

    # Skip if file is too new (< Twice the segment duration old [in seconds])
    age=$(( $(date +%s) - $(stat -c %Y "$file") ))
    [ "$age" -lt $((2 * SEGMENT_DURATION)) ] && continue

    caption=$(format_caption "$file")

    log "UPLOAD-$camera" "Uploading $file"

    if [ "$camera" = "main" ]; then
      cam_main_send_file "$file" "$caption"
    else
      cam_mini_send_file "$file" "$caption"
    fi

    if [ $? -eq 0 ]; then
      touch "$marker"
      log "UPLOAD-$camera" "Uploaded successfully"
      sleep 60
    else
      log "UPLOAD-$camera" "Failed upload $file"
    fi

  done < <(find "$OUTPUT_DIR/$camera" -type f -name "*.${ext}" | sort)
}

log "UPLOAD" "Uploader daemon started"

while true; do
  upload_new_files main &
  upload_new_files mini &

  wait   

  sleep "$POLL_INTERVAL"
done
