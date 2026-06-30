#!/usr/bin/env bash

set -euo pipefail

shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --------------------------------------------------------------------
# Load configuration
# --------------------------------------------------------------------

set -a
source "$PROJECT_ROOT/conf/restore_target.conf"
set +a

if (( $# != 1 )); then
    echo "Usage: $(basename "$0") <YYYY-MM-DD>"
    exit 1
fi

date="$1"

#
# Validate date
#

if ! date -d "$date" >/dev/null 2>&1; then
    echo "Error: Invalid date '$date'"
    exit 1
fi

DOWNLOAD_DIR="${DOWNLOAD_DIR%/}"

RESTORE_DIR="$DOWNLOAD_DIR/$camera/$date"

mkdir -p "$RESTORE_DIR"

echo "Camera        : $camera"
echo "Date          : $date"
echo "Restore Dir   : $RESTORE_DIR"
echo

# --------------------------------------------------------------------
# Decrypt and merge each hour
# --------------------------------------------------------------------

HOUR_SCRIPT="$SCRIPT_DIR/decrypt_merge_hour_job.sh"

for hour in $(seq -w 0 23); do

    echo
    echo "======================================================================"
    echo "Processing hour $hour"
    echo "======================================================================"
    echo

    bash "$HOUR_SCRIPT" "$date" "$hour"

done

# --------------------------------------------------------------------
# Merge hourly videos into one day video
# --------------------------------------------------------------------

echo
echo "Beginning day merge..."
echo

LIST_FILE="$RESTORE_DIR/day.txt"
: > "$LIST_FILE"

for hour in $(seq -w 0 23); do

    hour_dir=$(printf "%02d-%02d" "$((10#$hour))" "$((10#$hour + 1))")

    video="$RESTORE_DIR/$hour_dir/${camera}_${date}_${hour_dir}.mp4"

    if [[ ! -f "$video" ]]; then
        echo "Missing: $video"
        exit 1
    fi

    printf "file '%s'\n" "$video" >> "$LIST_FILE"

done

OUTPUT="$RESTORE_DIR/${camera}_${date}.mp4"

ffmpeg \
    -hide_banner \
    -loglevel warning \
    -f concat \
    -safe 0 \
    -i "$LIST_FILE" \
    -c copy \
    "$OUTPUT"

rm -f "$LIST_FILE"

echo
echo "Cleaning up hourly directories..."

for hour in $(seq -w 0 23); do

    hour_dir=$(printf "%02d-%02d" "$((10#$hour))" "$((10#$hour + 1))")

    rm -rf "$RESTORE_DIR/$hour_dir"

done

echo "Cleanup complete."

echo
echo "Day merge complete."
echo "Output:"
echo "  $OUTPUT"