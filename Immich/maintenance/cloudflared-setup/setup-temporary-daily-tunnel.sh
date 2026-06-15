#!/usr/bin/env bash

echo "Stopping old cloudflared processes if any..."
pkill cloudflared 2>/dev/null
sleep 2

while true; do

    echo
    echo "Starting Cloudflare tunnel..."

    URL=""

    coproc CF {
        cloudflared tunnel --url http://localhost:2283 2>&1
    }

    for i in {1..60}; do

        if read -r -t 1 line <&"${CF[0]}"; then

            echo "$line"

            if [[ $line =~ https://[A-Za-z0-9.-]+\.trycloudflare\.com ]]; then
                URL="${BASH_REMATCH[0]}"
                break
            fi

        fi

    done

    if [ -z "$URL" ]; then

        echo
        echo "Failed to obtain tunnel URL. Restarting..."

        kill "$CF_PID" 2>/dev/null
        wait "$CF_PID" 2>/dev/null

        sleep 5
        continue
    fi

    HOSTNAME=${URL#https://}

    echo
    echo "Tunnel URL found:"
    echo "$URL"

    echo
    echo "Hostname:"
    echo "$HOSTNAME"

    echo
    echo "Waiting for DNS propagation via 1.1.1.1..."

    for i in {1..60}; do

        echo "Attempt $i/60"

        if dig +short @"1.1.1.1" "$HOSTNAME" | grep -q .; then
            echo
            echo "Tunnel DNS is live."

            echo
            nslookup "$HOSTNAME" 1.1.1.1

            echo
            echo "Tunnel URL:"
            echo "$URL"

            exit 0
        fi

        sleep 1

    done

    echo
    echo "DNS propagation failed. Restarting..."

    kill "$CF_PID" 2>/dev/null
    wait "$CF_PID" 2>/dev/null

    sleep 5

done