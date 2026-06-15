#!/usr/bin/env bash

SESSION="cloudflare"

tmux kill-session -t "$SESSION" 2>/dev/null

tmux new-session -d \
    -s "$SESSION" \
    'cloudflared tunnel --url http://localhost:2283 2>&1'

echo "Waiting for Cloudflare tunnel..."

for i in {1..60}; do

    URL=$(
        tmux capture-pane -p -S -1000 -t "$SESSION" |
        awk '/trycloudflare.com/{
            match($0,/https:\/\/[A-Za-z0-9.-]+\.trycloudflare\.com/)
            if (RSTART) {
                print substr($0,RSTART,RLENGTH)
                exit
            }
        }'
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