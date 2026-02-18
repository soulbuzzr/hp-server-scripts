#!/bin/bash
set -u
set -o pipefail

# ================= RESOLVE HOME =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/Camera_Recording/lib/camera_lib.sh"

# ================= WAIT FOR NETWORK =================
wait_for_network "MINI-REC"

# ================= STARTUP =================
log "MINI-REC" "Mini camera recorder started"
cam_status_send "📹 Mini camera recorder started"

# ================= LOOP =================
while true; do

  # Wait until clock aligned hourly
  while ! is_segment_boundary; do
    sleep 0.1
  done

  cam_record_common mini

done
