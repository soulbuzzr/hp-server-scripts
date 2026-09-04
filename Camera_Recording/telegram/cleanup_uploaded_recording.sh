#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/Camera_Recording/lib/camera_lib.sh"

: "${MAX_AGE_SECONDS:?Missing MAX_AGE_SECONDS}"

BASE_DIR="$HOME/Ramdisk/Camera_Recording"

while true; do

  now_epoch=$(date +%s)

  for cam in main mini; do
    cam_dir="$BASE_DIR/$cam"

    [ -d "$cam_dir" ] || continue

    find "$cam_dir" -mindepth 3 -maxdepth 3 -type d | while read -r hourdir; do

      rel="${hourdir#$cam_dir/}"
      # rel = YYYY-MM/DD/HH
      year_month=$(echo "$rel" | cut -d'/' -f1)
      day=$(echo "$rel"        | cut -d'/' -f2)
      hour=$(echo "$rel"       | cut -d'/' -f3)

      # Epoch for the START of that hour block
      hour_start_epoch=$(date -d "${year_month}-${day} ${hour}:00:00" +%s 2>/dev/null) || {
        log "CAMERA RECORDING CLEANUP" "Skipping unparsable dir: $hourdir"
        continue
      }

      # Measure age from the END of the hour block (i.e. hour_start + 1h),
      # not the start. Using the start would make the last file written in
      # the hour (e.g. 12:59:xx in the "12" dir) eligible for deletion up to
      # ~59 minutes early, giving it only ~5h of guaranteed retention instead
      # of a true 6h floor. Anchoring on the end of the hour guarantees every
      # file in the folder is at least MAX_AGE_SECONDS old before deletion.
      hour_end_epoch=$(( hour_start_epoch + 3600 ))

      age=$(( now_epoch - hour_end_epoch ))

      if [ "$age" -ge "$MAX_AGE_SECONDS" ]; then
        [ -f "$hourdir/.merged" ] || log "CAMERA RECORDING CLEANUP" "WARNING: deleting $hourdir but .merged not found (may not be archived to HDD yet)"
        log "CAMERA RECORDING CLEANUP" "Force-cleaning $hourdir (age ${age}s, uploaded/merged status ignored)"
        rm -rf "$hourdir"
      fi

    done
  done

  sleep 120
done