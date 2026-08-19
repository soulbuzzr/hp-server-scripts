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

      # Force base-10 to avoid octal misparse of "08"/"09", then re-pad
      # for a clean numeric day.
      day=$((10#$day))

      # -------- Parse to epoch (skips/logs cleanly on malformed dirs) --------
      # GNU date does NOT accept "YYYY-MonthName-DD" (hyphenated), only
      # space-separated month-name forms. Use "Month DD YYYY" instead.
      archive_epoch=$(date -d "$month_name $day $year" +%s 2>/dev/null) || {
        log "RETENTION" "Skipping unparsable archive dir: $daydir"
        continue
      }

      if [ "$archive_epoch" -lt "$cutoff_epoch" ]; then
        log "RETENTION" "Deleting old archive: $daydir"
        rm -rf "$daydir"
      fi

    done

    # -------- Prune now-empty month and year dirs left behind --------
    # -mindepth 1 -maxdepth 2 covers both the month level (e.g. .../2026/August)
    # and the year level (e.g. .../2026) under $base in one pass. Sorting by
    # depth deepest-first (via find's natural top-down order won't work for
    # rmdir ordering, so we run it twice: months first, then years) ensures a
    # year only gets removed after its now-empty months are gone.
    find "$base" -mindepth 2 -maxdepth 2 -type d -empty -print0 2>/dev/null \
      | while IFS= read -r -d '' emptymonth; do
          log "RETENTION" "Removing empty month dir: $emptymonth"
          rmdir "$emptymonth" 2>/dev/null || true
        done

    find "$base" -mindepth 1 -maxdepth 1 -type d -empty -print0 2>/dev/null \
      | while IFS= read -r -d '' emptyyear; do
          log "RETENTION" "Removing empty year dir: $emptyyear"
          rmdir "$emptyyear" 2>/dev/null || true
        done

  done

  sleep 3600

done