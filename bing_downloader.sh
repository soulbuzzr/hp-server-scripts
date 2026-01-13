#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------
# Paths and DB
# ---------------------------------------------
RAMDISK="$HOME/Ramdisk"
OUT="$HOME/Bing"
DB="$OUT/hashes.txt"

mkdir -p "$RAMDISK" "$OUT"
touch "$DB"

# ---------------------------------------------
# Regions you want to download from
# ---------------------------------------------
regions=(
  en-US en-CA fr-CA es-US es-MX pt-BR es-AR es-CL es-CO es-PE es-VE
  en-GB en-IE fr-FR de-DE it-IT es-ES pt-PT nl-NL nl-BE fr-BE
  sv-SE nb-NO da-DK fi-FI cs-CZ pl-PL tr-TR ru-RU
  en-IN hi-IN en-SG zh-CN zh-HK zh-TW ja-JP ko-KR en-PH
  en-MY ms-MY id-ID th-TH vi-VN
  ar-SA ar-EG ar-AE he-IL en-ZA
)

# ---------------------------------------------
# Loop regions
# ---------------------------------------------
for region in "${regions[@]}"; do
    echo
    echo "========== REGION: $region =========="

    API="https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=16&mkt=$region"
    json=$(curl -s "$API")

    count=$(echo "$json" | jq '.images | length')

    for (( idx=0; idx<count; idx++ )); do

        # Get region's own title
        region_title=$(echo "$json" | jq -r ".images[$idx].title")

        # Sanitize filename: remove invalid characters / quotes
        clean_title=$(printf "%s" "$region_title" \
            | sed 's/[\/:*?"<>|]//g' \
            | tr -d "'" \
            | tr -d '\\')

        # If title ends empty (rare), generate fallback name
        if [[ -z "$clean_title" ]]; then
            clean_title="Image_${idx}"
        fi

        base=$(echo "$json" | jq -r ".images[$idx].urlbase")

        if [[ -z "$base" || "$base" == "null" ]]; then
            echo "No image for index $idx in $region"
            continue
        fi

        url="https://www.bing.com${base}_UHD.jpg"
        tmp="$RAMDISK/${clean_title}_${region}.jpg"
        final="$OUT/${clean_title} (${region}).jpg"

        echo "Downloading: ${clean_title} (${region})"

        curl -s -L "$url" -o "$tmp"

        HASH=$(sha256sum "$tmp" | awk '{print $1}')

        # Skip duplicates across regions
        if grep -q "^${HASH}$" "$DB"; then
            echo "Duplicate → ${clean_title} (${region})"
            rm -f "$tmp"
            continue
        fi

        echo "$HASH" >> "$DB"
        mv "$tmp" "$final"

        echo "Saved → $final"
    done
done

echo
echo "✔️ All unique regional images saved in ~/Bing/ (with region titles)"
