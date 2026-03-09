#!/bin/bash

# ==========================
# Configuration
# ==========================
COUNT=5
TIMEOUT=3
INTERVAL=10

HOSTS=(
    "mtn-1.cnicdn.com"
    "mtn-2.cnicdn.com"
    "google.com"
)

LOG_DIR="/home/mrtc/scripts/logs"
LOG_FILE="$LOG_DIR/ping_monitor.log"

# ==========================
# Setup
# ==========================
mkdir -p "$LOG_DIR"

echo "Starting ping monitor"
echo "Logging to $LOG_FILE"

# ==========================
# Main Loop
# ==========================
while true; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    for HOST in "${HOSTS[@]}"; do
        OUTPUT=$(ping -c $COUNT -W $TIMEOUT -q "$HOST" 2>&1)
        STATUS=$?

        # Check if ping failed completely
        if [ $STATUS -ne 0 ]; then
            echo "$TIMESTAMP | $HOST | Ping failed (DNS or unreachable)" >> "$LOG_FILE"
            continue
        fi

        # Extract packet loss %
        PACKETLOSS=$(echo "$OUTPUT" | grep -oP '\d+(?=% packet loss)')

        # Extract avg latency
        AVG_LATENCY=$(echo "$OUTPUT" | awk -F'/' '/rtt/ {print $5}')

        if [ -z "$PACKETLOSS" ]; then
            echo "$TIMESTAMP | $HOST | Could not parse packet loss" >> "$LOG_FILE"
            continue
        fi

        echo "$TIMESTAMP | $HOST | Packet loss: ${PACKETLOSS}% | Avg Latency: ${AVG_LATENCY} ms" >> "$LOG_FILE"
    done

    sleep $INTERVAL
done
