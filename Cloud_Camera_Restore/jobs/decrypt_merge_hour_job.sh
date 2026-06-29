#!/usr/bin/env bash

set -euo pipefail

shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --------------------------------------------------------------------
# Load configuration
# --------------------------------------------------------------------

set -a
source "$PROJECT_ROOT/env/telegram_app.env"
source "$PROJECT_ROOT/conf/restore_target.conf"
set +a

: "${ENCRYPTION_PASSWORD:?ENCRYPTION_PASSWORD not set}"

if (( $# != 2 )); then
    echo "Usage: $(basename "$0") <YYYY-MM-DD> <HH>"
    exit 1
fi

date="$1"
hour="$2"

#
# Validate date
#

if ! date -d "$date" >/dev/null 2>&1; then
    echo "Error: Invalid date '$date'"
    exit 1
fi

#
# Validate hour
#

if ! [[ "$hour" =~ ^([01][0-9]|2[0-3])$ ]]; then
    echo "Error: Hour must be between 00 and 23"
    exit 1
fi

DOWNLOAD_DIR="${DOWNLOAD_DIR%/}"

RESTORE_DIR="$DOWNLOAD_DIR/$camera/$date/$hour"

EXTRACT_DIR="$RESTORE_DIR/extracted"

mkdir -p "$EXTRACT_DIR"

echo "Camera        : $camera"
echo "Date          : $date"
echo "Hour          : $hour"
echo "Restore Dir   : $RESTORE_DIR"
echo "Extract Dir   : $EXTRACT_DIR"
echo

# --------------------------------------------------------------------
# Find archives
# --------------------------------------------------------------------

archives=("$RESTORE_DIR"/raw/*.7z)

if (( ${#archives[@]} == 0 )); then
    echo "No archives found."
    exit 1
fi

echo "Found ${#archives[@]} archive(s)."
echo

echo "Beginning decryption..."
echo

THREADS=$(nproc)

for archive in "${archives[@]}"; do
    (
        echo "Decrypting $(basename "$archive")"

        7z x \
            -y \
            -p"$ENCRYPTION_PASSWORD" \
            -o"$EXTRACT_DIR" \
            "$archive" \
            >/dev/null
    ) &

    while (( $(jobs -rp | wc -l) >= THREADS )); do
        wait -n
    done
done

wait
echo
echo "Decryption complete."

echo
echo "Beginning merge..."
echo

videos=("$EXTRACT_DIR"/*.mp4)

if (( ${#videos[@]} == 0 )); then
    echo "No extracted videos found."
    exit 1
fi

IFS=$'\n' videos=($(printf "%s\n" "${videos[@]}" | sort))
unset IFS

LIST_FILE="$RESTORE_DIR/files.txt"
: > "$LIST_FILE"

for video in "${videos[@]}"; do
    printf "file '%s'\n" "$video" >> "$LIST_FILE"
done

OUTPUT="$RESTORE_DIR/${camera}_${date}_${hour}.mp4"

ffmpeg \
    -hide_banner \
    -loglevel warning \
    -f concat \
    -safe 0 \
    -i "$LIST_FILE" \
    -c copy \
    "$OUTPUT"

rm -rf "$EXTRACT_DIR"
rm -rf "$RESTORE_DIR/raw"
rm -f "$LIST_FILE"

echo
echo "Merge complete."
echo "Output:"
echo "  $OUTPUT"