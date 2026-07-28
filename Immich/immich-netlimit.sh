#!/bin/bash
set -e
IF=br-immich
RATE=240mbit

# wait for the bridge (created by docker compose at startup)
for i in $(seq 60); do ip link show "$IF" &>/dev/null && break; sleep 1; done
ip link show "$IF" &>/dev/null || { echo "$IF never appeared"; exit 1; }

# ifb device to shape container-upload direction
modprobe ifb || true
ip link add ifb-immich type ifb 2>/dev/null || true
ip link set ifb-immich up

# clean slate (idempotent re-runs)
tc qdisc del dev "$IF" root 2>/dev/null || true
tc qdisc del dev "$IF" ingress 2>/dev/null || true
tc qdisc del dev ifb-immich root 2>/dev/null || true

# container DOWNLOAD (host -> containers = egress on the bridge)
tc qdisc add dev "$IF" root cake bandwidth $RATE besteffort

# container UPLOAD (containers -> world = ingress on the bridge, redirected to ifb)
tc qdisc add dev "$IF" handle ffff: ingress
tc filter add dev "$IF" parent ffff: matchall action mirred egress redirect dev ifb-immich
tc qdisc add dev ifb-immich root cake bandwidth $RATE besteffort