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
log "MINI_CAMERA" "Clock aligned. Starting recording."
cam_status_send "🎥 Mini camera recording started at $(date '+%F %T')"

# ================= START RECORDING =================
cam_record_common mini
