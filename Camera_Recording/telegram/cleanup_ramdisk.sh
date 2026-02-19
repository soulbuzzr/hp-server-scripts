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

      if [ "$rel" = "$current_hour" ]; then
        continue
      fi

      if [ -f "$hourdir/.merged" ]; then
        log "CLEANUP" "Cleaning $hourdir"

        rm -f "$hourdir"/*.mp4 2>/dev/null || true
        rm -f "$hourdir"/*.mkv 2>/dev/null || true
        rm -f "$hourdir"/*.uploaded 2>/dev/null || true

        if [ "$(ls -A "$hourdir")" = ".merged" ]; then
          rm -f "$hourdir/.merged"
          rmdir "$hourdir" 2>/dev/null || true
        fi
      fi
    done
  done

  sleep 120
done