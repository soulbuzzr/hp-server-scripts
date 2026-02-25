#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/Camera_Recording/lib/camera_lib.sh"

BASE_DIR="$HOME/Ramdisk/Camera_Recording"

while true; do

  current_hour=$(date +"%Y-%m/%d/%H")

  for cam in main mini; do
    find "$BASE_DIR/$cam" -mindepth 3 -maxdepth 3 -type d | while read -r hourdir; do

      rel="${hourdir#$BASE_DIR/$cam/}"

      # Skip current hour
      if [ "$rel" = "$current_hour" ]; then
        continue
      fi

      # Only consider merged hours
      if [ ! -f "$hourdir/.merged" ]; then
        continue
      fi

      # Ensure all video files are uploaded
      all_uploaded=true

      shopt -s nullglob
      for video in "$hourdir"/*.mp4 "$hourdir"/*.mkv; do
        [ -f "$video" ] || continue

        if [ ! -f "${video}.uploaded" ]; then
          all_uploaded=false
          break
        fi
      done
      shopt -u nullglob

      if [ "$all_uploaded" = true ]; then
        log "CAMERA RECORDING CLEANUP" "Cleaning $hourdir (merged + uploaded)"

        rm -f "$hourdir"/*.mp4 2>/dev/null || true
        rm -f "$hourdir"/*.mkv 2>/dev/null || true
        rm -f "$hourdir"/*.uploaded 2>/dev/null || true

        rm -f "$hourdir/.merged"

        rmdir "$hourdir" 2>/dev/null || true
      fi

    done
  done

  sleep 120
done