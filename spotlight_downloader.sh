#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------
# Unique temp workspace (per run) in /tmp
# ---------------------------------------------
TMP_BASE="$(mktemp -d /tmp/spotlight.XXXXXX)"
TMP_DL="$TMP_BASE/downloads"

OUT="$HOME/Spotlight"
DB="$OUT/hashes.txt"

mkdir -p "$TMP_DL" "$OUT"
touch "$DB"

# ---------------------------------------------
# Cleanup on exit (normal or error)
# ---------------------------------------------
cleanup() {
  rm -rf "$TMP_BASE"
}
trap cleanup EXIT

# ---------------------------------------------
# API
# ---------------------------------------------
API="https://fd.api.iris.microsoft.com/v4/api/selection?bcnt=1&country=IN&fmt=json&locale=en-IN&placement=88000820"

# ---------------------------------------------
# Main loop
# ---------------------------------------------
while true; do
    # Get JSON block
    json=$(curl -s "$API" | jq '.batchrsp.items[].item | fromjson | .ad')

    # Extract title + URL
    title_raw=$(echo "$json" | jq -r '.title')
    url=$(echo "$json" | jq -r '.landscapeImage.asset')

    title=$(echo "$title_raw" | iconv -c -t ASCII//TRANSLIT | sed 's/[^A-Za-z0-9._-]/_/g')

    TMP_FILE="$TMP_DL/$title.jpg"
    curl -s -L -o "$TMP" "$url"

    # Compute hash
    HASH=$(sha256sum "$TMP_FILE" | awk '{print $1}')

    # Check duplicate
    if grep -q "$HASH" "$DB"; then
        echo "Duplicate - $title"
        rm -f "$TMP_FILE"
    else
        echo "NEW IMAGE FOUND - $title"
        echo "$HASH" >> "$DB"
        mv "$TMP_FILE" "$OUT/${title}_${HASH}.jpg"
    fi

    # 8 images/sec → 0.125s
    sleep 0.125
done
