#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/Camera_Recording/lib/camera_lib.sh"

: "${ARCHIVE_RETENTION_DAYS:?Missing ARCHIVE_RETENTION_DAYS}"

log "RETENTION" "Archive retention daemon started (Keep ${ARCHIVE_RETENTION_DAYS} days)"

while true; do

  # Calculate cutoff date
  cutoff_date=$(date -d "-${ARCHIVE_RETENTION_DAYS} days" +%Y-%m-%d)

  for cam_root in "Main-camera" "Mini-camera"; do

    base="$ARCHIVE_DIR/$cam_root"

    [ -d "$base" ] || continue

    # Traverse year/month/day folders
    find "$base" -mindepth 3 -maxdepth 3 -type d | while read -r daydir; do

      # Extract date from path
      # Structure: /Main-camera/2026/February/25th
      year=$(echo "$daydir" | awk -F/ '{print $(NF-2)}')
      month_name=$(echo "$daydir" | awk -F/ '{print $(NF-1)}')
      day_suffix=$(basename "$daydir")

      # Remove st/nd/rd/th
      day=$(echo "$day_suffix" | sed 's/\(st\|nd\|rd\|th\)$//')

      # Convert month name to number
      month_num=$(date -d "$month_name 1" +%m)

      archive_date="${year}-${month_num}-${day}"

      # Compare dates
      if [[ "$archive_date" < "$cutoff_date" ]]; then
        log "RETENTION" "Deleting old archive: $daydir"
        rm -rf "$daydir"
      fi

    done

  done

  sleep 3600  

done