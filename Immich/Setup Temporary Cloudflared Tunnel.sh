#!/usr/bin/env bash

SESSION="cloudflare"
LOG="/tmp/cloudflared.log"

while true; do

    echo
    echo "Starting Cloudflare tunnel..."

    rm -f "$LOG"

    tmux kill-session -t "$SESSION" 2>/dev/null

    tmux new-session -d -s "$SESSION" \
        "cloudflared tunnel --url http://localhost:2283 > $LOG 2>&1"

    echo "Waiting for tunnel URL..."

    URL=""

    for i in {1..5}; do

        URL=$(
            grep -oE 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$LOG" |
            head -n1
        )

        if [ -n "$URL" ]; then
            break
        fi

        sleep 1
    done

    if [ -z "$URL" ]; then
        echo "Failed to obtain tunnel URL. Restarting..."
        continue
    fi

    echo
    echo "Tunnel URL found:"
    echo "$URL"

    echo "Checking reachability..."

    for i in {1..60}; do

        if curl -fsS \
            --connect-timeout 5 \
            --max-time 10 \
            "$URL" >/dev/null 2>&1; then

            echo
            echo "Tunnel is reachable."
            echo "$URL"
            exit 0
        fi

        sleep 1
    done

    echo "Tunnel not reachable after 60 seconds. Restarting..."

    tmux kill-session -t "$SESSION" 2>/dev/null

    sleep 2

done