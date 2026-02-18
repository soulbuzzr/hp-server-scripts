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
wait_for_network "MAIN-REC"

# ================= STARTUP =================
log "MAIN-REC" "Main camera recorder started"
cam_status_send "📹 Main camera recorder started"

# ================= START RECORDING =================


# Wait until clock aligned hourly
while ! is_hour_boundary; do
  sleep 1
done

cam_record_common main


