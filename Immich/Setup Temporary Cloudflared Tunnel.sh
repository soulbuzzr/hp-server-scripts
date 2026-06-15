#!/usr/bin/env bash

SESSION="cloudflare"
LOG="/tmp/cloudflared.log"

rm -f "$LOG"

tmux kill-session -t "$SESSION" 2>/dev/null

tmux new-session -d -s "$SESSION" \
    "cloudflared tunnel --url http://localhost:2283 > $LOG 2>&1"

echo "Waiting for Cloudflare tunnel..."

for i in {1..60}; do

    URL=$(
        grep -oE 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$LOG" |
        head -n1
    )

    if [ -n "$URL" ]; then
        echo
        echo "Tunnel URL:"
        echo "$URL"
        exit 0
    fi

    sleep 1
done

echo "Failed to obtain tunnel URL"
exit 1