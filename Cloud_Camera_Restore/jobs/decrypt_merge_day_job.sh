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

DOWNLOAD_DIR="${DOWNLOAD_DIR%/}"

RESTORE_DIR="$DOWNLOAD_DIR/$camera/$date"

EXTRACT_DIR="$RESTORE_DIR/extracted"

mkdir -p "$EXTRACT_DIR"

echo "Camera        : $camera"
echo "Date          : $date"
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
        name=$(basename "$archive")

        echo "Decrypting $name"

        if 7z x \
            -y \
            -p"$ENCRYPTION_PASSWORD" \
            -o"$EXTRACT_DIR" \
            "$archive" \
            >/dev/null
        then
            rm -f "$archive"
            echo "✓ $name"
        else
            echo "✗ $name"
            exit 1
        fi
    ) &

    while (( $(jobs -rp | wc -l) >= THREADS )); do
        wait -n
    done
done

wait
echo
echo "Decryption complete."

echo
echo "Beginning hourly merge..."
echo

mapfile -t files < <(
    find "$EXTRACT_DIR" \
        -maxdepth 1 \
        -type f \
        -name "${camera}_${date}_*.mp4" |
    sort
)

if (( ${#files[@]} == 0 )); then
    echo "No extracted videos found."
    exit 1
fi

hours=()
last_hour=""

for file in "${files[@]}"; do

    name=$(basename "$file")

    time_part=${name##*_}
    hour=${time_part%%-*}

    if [[ "$hour" != "$last_hour" ]]; then
        hours+=("$hour")
        last_hour="$hour"
    fi

done

for hour in "${hours[@]}"; do

    echo
    echo "Merging hour $hour..."

    mapfile -t videos < <(
        find "$EXTRACT_DIR" \
            -maxdepth 1 \
            -type f \
            -name "${camera}_${date}_${hour}-*.mp4" |
        sort
    )

    LIST_FILE="$RESTORE_DIR/hour_${hour}.txt"

    printf "file '%s'\n" "${videos[@]}" > "$LIST_FILE"

    OUTPUT="$RESTORE_DIR/${camera}_${date}_${hour}_hour.mp4"

    ffmpeg \
        -hide_banner \
        -loglevel warning \
        -f concat \
        -safe 0 \
        -i "$LIST_FILE" \
        -c copy \
        "$OUTPUT"

    rm -f "${videos[@]}"
    rm -f "$LIST_FILE"

    echo "Created $(basename "$OUTPUT")"

done

echo
echo "Hourly merge complete."
