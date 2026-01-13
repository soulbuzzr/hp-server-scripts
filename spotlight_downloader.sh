#!/usr/bin/env bash
set -euo pipefail

RAMDISK="$HOME/Ramdisk"
OUT="$HOME/Spotlight"
DB="$OUT/hashes.txt"

mkdir -p "$RAMDISK" "$OUT"
touch "$DB"

API="https://fd.api.iris.microsoft.com/v4/api/selection?bcnt=1&country=IN&fmt=json&locale=en-IN&placement=88000820"

while true; do
    # Get JSON block
    json=$(curl -s "$API" | jq '.batchrsp.items[].item | fromjson | .ad')

    # Extract title + URL
    title_raw=$(echo "$json" | jq -r '.title')
    url=$(echo "$json" | jq -r '.landscapeImage.asset')

    title=$(echo "$title_raw" | iconv -c -t ASCII//TRANSLIT | sed 's/[^A-Za-z0-9._-]/_/g')

    # Download to RAMDISK
    TMP="$RAMDISK/$title.jpg"
    curl -s -L -o "$TMP" "$url"

    # Compute hash
    HASH=$(sha256sum "$TMP" | awk '{print $1}')

    # Check duplicate
    if grep -q "$HASH" "$DB"; then
        echo "Duplicate - $title"
        rm "$TMP"
    else
        echo "NEW IMAGE FOUND - $title"
        echo "$HASH" >> "$DB"
        mv "$TMP" "$OUT/${title}_${HASH}.jpg"
    fi

    # 8 images per second → 0.125 sec sleep
    sleep 0.125
done
