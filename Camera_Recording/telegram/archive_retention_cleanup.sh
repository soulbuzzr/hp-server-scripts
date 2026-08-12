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

  # Calculate cutoff date (as epoch seconds for a reliable comparison)
  cutoff_epoch=$(date -d "-${ARCHIVE_RETENTION_DAYS} days" +%s)

  for camera in main mini; do

    cam_root=$(camera_archive_root "$camera") || continue
    base="$ARCHIVE_DIR/$cam_root"

    [ -d "$base" ] || continue

    # Traverse year/month/day folders
    find "$base" -mindepth 3 -maxdepth 3 -type d | while read -r daydir; do

      # Extract date from path
      # Structure: /Main-camera/2026/February/25th
      year=$(echo "$daydir" | awk -F/ '{print $(NF-2)}')
      month_name=$(echo "$daydir" | awk -F/ '{print $(NF-1)}')
      day_suffix_str=$(basename "$daydir")

      # Remove st/nd/rd/th
      day=$(echo "$day_suffix_str" | sed 's/\(st\|nd\|rd\|th\)$//')

      # -------- Parse to epoch (skips/logs cleanly on malformed dirs) --------
      archive_epoch=$(date -d "$year-$month_name-$day" +%s 2>/dev/null) || {
        log "RETENTION" "Skipping unparsable archive dir: $daydir"
        continue
      }

      if [ "$archive_epoch" -lt "$cutoff_epoch" ]; then
        log "RETENTION" "Deleting old archive: $daydir"
        rm -rf "$daydir"
      fi

    done

  done

  sleep 3600

done