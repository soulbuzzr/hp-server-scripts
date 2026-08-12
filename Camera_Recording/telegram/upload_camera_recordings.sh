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
  local camera_dir
  ext=$(file_extension "$camera")
  local newest_file=""

  camera_dir="$OUTPUT_DIR/$camera"

  [ ! -d "$camera_dir" ] && return

  # Skip newest segment (likely still being written by FFmpeg)
  newest_file=$(find "$camera_dir" -type f -name "*.${ext}" | sort | tail -n1)

  while IFS= read -r file; do
    uploaded_marker="${file}.uploaded"
    overflow_marker="${file}.file-size-overflow"

    # Skip if already handled
    [ -f "$uploaded_marker" ] && continue
    [ -f "$overflow_marker" ] && continue

    # Skip newest segment
    [ "$file" = "$newest_file" ] && continue

    caption=$(format_caption "$file")

    # -------- Encrypt File --------
    encrypted_file="${file}.7z"

    if [ ! -f "$encrypted_file" ]; then
      log "UPLOAD-$camera" "Encrypting $file"

      7z a \
        -mx=0 \
        -mhe=on \
        -p"$ENCRYPTION_PASSWORD" \
        "$encrypted_file" \
        "$file" >/dev/null
    fi

    log "UPLOAD-$camera" "Uploading $encrypted_file"

    # -------- Check file size --------
    encrypted_size=$(stat -c %s "$encrypted_file")

    if [ "$encrypted_size" -gt "$MAX_UPLOAD_SIZE" ]; then
      log "UPLOAD-$camera" "Encrypted file too large: $encrypted_file ($encrypted_size bytes)"
      touch "$overflow_marker"
      continue
    fi

    # -------- Send Encrypted File --------
    # Was: if/else dispatching to cam_main_send_file / cam_mini_send_file.
    # Now handled centrally in the lib.
    response=$(cam_send_file "$camera" "$encrypted_file" "$caption" || true)

    # -------- Validate JSON Safely --------
    if echo "$response" | jq -e . >/dev/null 2>&1; then

        if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
            touch "$uploaded_marker"
            touch "${encrypted_file}.uploaded"

            # Direct Cleanup
            rm -f "$encrypted_file"

            log "UPLOAD-$camera" "Encrypted upload successful"
            sleep 2    # Safety Net for Telegram simulatenous upload limit
        else
            error_msg=$(echo "$response" | jq -r '.description // "Unknown error"')
            log "UPLOAD-$camera" "Telegram API error: $error_msg"
            cam_status_send "Upload $camera failed: $error_msg"
        fi

    else
        log "UPLOAD-$camera" "Invalid JSON / Network failure: ${response}"
        cam_status_send "Upload $camera failed: Network or curl error"
    fi

  done < <(find "$camera_dir" -type f -name "*.${ext}" | sort)
}

log "UPLOAD" "Uploader daemon started"

while true; do
  upload_new_files main &
  upload_new_files mini &

  wait

  sleep "$POLL_INTERVAL"
done