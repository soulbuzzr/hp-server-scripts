#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/hpserver"
fi

BASE_DIR="$HOME/Ramdisk/Camera_Recording"

create_tree_for_date() {
    local target_date="$1"
    local start_hour="$2"

    local year_month day
    year_month=$(date -d "$target_date" +%Y-%m)
    day=$(date -d "$target_date" +%d)

    for cam in main mini; do
        for hour in $(seq "$start_hour" 23); do
            printf -v HOUR_PAD "%02d" "$hour"
            mkdir -p "$BASE_DIR/$cam/$year_month/$day/$HOUR_PAD"
        done
    done
}

cleanup_old_empty_dirs() {
    local today_month today_day today_hour
    today_month=$(date +%Y-%m)
    today_day=$(date +%d)
    today_hour=$(date +%H)

    for cam in main mini; do
        cam_dir="$BASE_DIR/$cam"

        # Remove old empty months
        find "$cam_dir" -mindepth 1 -maxdepth 1 -type d ! -name "$today_month" \
            -exec rmdir {} 2>/dev/null \;

        month_dir="$cam_dir/$today_month"

        # Remove past empty days
        find "$month_dir" -mindepth 1 -maxdepth 1 -type d \
            ! -name "$today_day" \
            -exec rmdir {} 2>/dev/null \;

        today_dir="$month_dir/$today_day"

        # Remove past empty hours
        if [ -d "$today_dir" ]; then
            for hour_dir in "$today_dir"/*; do
                hour=$(basename "$hour_dir")
                if [ "$hour" -lt "$today_hour" ]; then
                    rmdir "$hour_dir" 2>/dev/null || true
                fi
            done
        fi
    done
}

echo "Camera Tree Daemon Started"

while true; do

    now_hour=$(date +%H)
    now_min=$(date +%M)

    today=$(date +%Y-%m-%d)
    tomorrow=$(date -d tomorrow +%Y-%m-%d)

    # ---- Always ensure today's structure ----
    create_tree_for_date "$today" "$now_hour"

    # ---- If time >= 23:30 create tomorrow fully ----
    if [ "$now_hour" -eq 23 ] && [ "$now_min" -ge 30 ]; then
        create_tree_for_date "$tomorrow" 0
    fi

    # ---- Cleanup old empty dirs safely ----
    cleanup_old_empty_dirs

    sleep 900   # 15 minutes
done
