#!/bin/sh
# rndc-sidecar: watches /reload/ for trigger files and reloads named zones
# Runs on host network so it can reach 127.0.0.1:953
# Trigger file format: /reload/<zone>  (e.g. /reload/home.arpa)
set -e

RELOAD_DIR="/reload"
RNDC_KEY="/rndc.key"

mkdir -p "$RELOAD_DIR"

echo "[rndc-sidecar] watching $RELOAD_DIR for zone reload triggers..."

while true; do
  for trigger in "$RELOAD_DIR"/*; do
    [ -f "$trigger" ] || continue
    ZONE="$(basename "$trigger")"
    echo "[rndc-sidecar] reloading zone: $ZONE"
    if /usr/sbin/rndc -s 127.0.0.1 -p 953 -k "$RNDC_KEY" reload "$ZONE"; then
      echo "[rndc-sidecar] reloaded $ZONE"
    else
      echo "[rndc-sidecar] ERROR: failed to reload $ZONE" >&2
    fi
    rm -f "$trigger"
  done
  sleep 2
done
