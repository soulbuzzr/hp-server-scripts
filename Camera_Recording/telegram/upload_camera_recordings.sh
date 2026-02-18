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

    # Skip if file is too new (< 600 sec old)
    age=$(( $(date +%s) - $(stat -c %Y "$file") ))
    [ "$age" -lt 600 ] && continue

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

merge_completed_hour() {
  local camera="$1"

  current_hour=$(date +"%Y-%m/%d/%H")

  find "$OUTPUT_DIR/$camera" -mindepth 3 -maxdepth 3 -type d | while read -r hourdir; do
    rel="${hourdir#$OUTPUT_DIR/$camera/}"

    if [ "$rel" = "$current_hour" ]; then
      continue
    fi

    # If already archived, skip
    if [ -f "$hourdir/.merged" ]; then
      continue
    fi

    log "MERGE-$camera" "Merging $hourdir"

    tmp_list="$hourdir/files.txt"
    ls "$hourdir"/*.$(file_extension "$camera") > "$tmp_list"

    merged_file="$ARCHIVE_DIR/${camera}_$(echo "$rel" | tr '/' '_').$(file_extension "$camera")"
    mkdir -p "$ARCHIVE_DIR"

    ffmpeg -f concat -safe 0 -i <(sed "s/^/file '/; s/$/'/" "$tmp_list") \
      -c copy "$merged_file"

    if [ $? -eq 0 ]; then
      touch "$hourdir/.merged"
      rm -f "$hourdir"/*.$(file_extension "$camera")
      rm -f "$hourdir"/*.uploaded
      log "MERGE-$camera" "Archived $merged_file"
    fi
  done
}

log "UPLOAD" "Uploader daemon started"

while true; do
  upload_new_files main &
  upload_new_files mini &

  wait   

  sleep "$POLL_INTERVAL"
done
