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
wait_for_network "MAIN_CAMERA"

# ================= STARTUP =================
log "MAIN_CAMERA" "Starting recording...."
cam_status_send "🎥 Main camera recording started at $(date '+%F %T')"

# ================= START RECORDING =================
while true; do
  cam_record_common main
  cam_status_send "⚠️ Main camera restarting recording"
  sleep 5
done