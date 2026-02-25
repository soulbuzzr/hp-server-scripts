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
    uploaded_marker="${file}.uploaded"
    overflow_marker="${file}.file-size-overflow"

    # Skip if already handled
    [ -f "$uploaded_marker" ] && continue
    [ -f "$overflow_marker" ] && continue

    # -------- Check file size --------
    filesize=$(stat -c %s "$file")

    if [ "$filesize" -gt "$MAX_UPLOAD_SIZE" ]; then
      log "UPLOAD-$camera" "File too large: $file ($filesize bytes)"
      touch "$overflow_marker"
      continue
    fi

    # Skip if file is too new (< 2 × SEGMENT_DURATION seconds old)
    age=$(( $(date +%s) - $(stat -c %Y "$file") ))
    [ "$age" -lt $((2 * SEGMENT_DURATION)) ] && continue

    caption=$(format_caption "$file")

    log "UPLOAD-$camera" "Uploading $file"

    # -------- Send File --------
    if [ "$camera" = "main" ]; then
      response=$(cam_main_send_file "$file" "$caption" || true)
    else
      response=$(cam_mini_send_file "$file" "$caption" || true)
    fi

    # -------- Validate JSON Safely --------
    if echo "$response" | jq -e '.ok == true' >/dev/null 2>&1; then
      touch "$uploaded_marker"
      log "UPLOAD-$camera" "Uploaded successfully"
      sleep 60
    else
      log "UPLOAD-$camera" "Upload failed. Response: ${response:-EMPTY}"
      cam_status_send "Upload $camera camera failed. API Response: ${response:-EMPTY}"
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