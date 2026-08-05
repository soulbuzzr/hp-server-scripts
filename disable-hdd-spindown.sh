#!/bin/bash
#
# disable-hdd-spindown.sh
# For every rotational block device (/sys/block/sdX/queue/rotational == 1),
# disable APM spin-down via hdparm. Runs at boot via systemd.

for path in /sys/block/sd*; do
    dev="/dev/$(basename "$path")"
    rotational=$(cat "$path/queue/rotational" 2>/dev/null)

    if [ "$rotational" = "1" ]; then
        echo "Disabling spin-down on $dev (rotational)"
        hdparm -B 255 -S 0 "$dev"
    fi
done