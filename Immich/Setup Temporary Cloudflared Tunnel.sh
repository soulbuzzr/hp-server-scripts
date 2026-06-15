#!/usr/bin/env bash

while true; do

    echo
    echo "Starting Cloudflare tunnel..."

    URL=""

    coproc CF {
        cloudflared tunnel --url http://localhost:2283 2>&1
    }

    while read -r line <&"${CF[0]}"; do

        echo "$line"

        if [[ $line =~ https://[A-Za-z0-9.-]+\.trycloudflare\.com ]]; then
            URL="${BASH_REMATCH[0]}"
            break
        fi

    done

    if [ -z "$URL" ]; then
        echo "Failed to obtain tunnel URL. Restarting..."

        kill "$CF_PID" 2>/dev/null
        wait "$CF_PID" 2>/dev/null

        sleep 5
        continue
    fi

    echo
    echo "Tunnel URL found:"
    echo "$URL"

    HOSTNAME=${URL#https://}

    echo
    echo "Waiting for DNS propagation..."

    DNS_OK=0

    for i in {1..60}; do

        if getent hosts "$HOSTNAME" >/dev/null 2>&1; then
            DNS_OK=1
            break
        fi

        sleep 1
    done

    if [ "$DNS_OK" -eq 1 ]; then

        echo
        echo "Tunnel DNS is live."
        echo "$URL"

        exit 0
    fi

    echo
    echo "DNS propagation failed. Restarting..."

    kill "$CF_PID" 2>/dev/null
    wait "$CF_PID" 2>/dev/null

    sleep 5

done