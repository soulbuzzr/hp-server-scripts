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

  find "$OUTPUT_DIR/$camera" -type f -name "*.$(file_extension "$camera")" | while read -r file; do
    marker="${file}.uploaded"

    if [ -f "$marker" ]; then
      continue
    fi

    caption=$(format_caption "$file")

    log "UPLOAD-$camera" "Uploading $file"
    cam_main_send_file "$file" "$caption"

    touch "$marker"
  done
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
  upload_new_files main
  upload_new_files mini

#   merge_completed_hour main
#   merge_completed_hour mini

  sleep "$POLL_INTERVAL"
done
