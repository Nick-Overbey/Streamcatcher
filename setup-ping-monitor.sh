#!/bin/bash

set -e

echo "========================================"
echo " Ping Monitor Setup"
echo "========================================"

# ----------------------------
# Ask for Operator Name
# ----------------------------
read -p "Enter operator name (example: star, acme, xyz): " OPERATOR

if [[ -z "$OPERATOR" ]]; then
    echo "Operator name cannot be empty."
    exit 1
fi

# Normalize operator name
OPERATOR=$(echo "$OPERATOR" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

# ----------------------------
# Ask for CDN servers
# ----------------------------
read -p "How many CDN servers do you have? " CDN_COUNT

if ! [[ "$CDN_COUNT" =~ ^[0-9]+$ ]] || [ "$CDN_COUNT" -le 0 ]; then
    echo "Invalid number."
    exit 1
fi

HOSTS=()

for ((i=1; i<=CDN_COUNT; i++)); do
    read -p "Enter CDN server URL #$i: " URL
    HOSTS+=(""$URL"")
done

# Always include Google baseline
HOSTS+=(""google.com"")

# ----------------------------
# Resolve home directory safely
# ----------------------------
USER_HOME=$(eval echo "~$(whoami)")

SCRIPTS_DIR="$USER_HOME/scripts"
LOG_DIR="$SCRIPTS_DIR/logs"

mkdir -p "$SCRIPTS_DIR"
mkdir -p "$LOG_DIR"

echo ""
echo "Scripts directory: $SCRIPTS_DIR"
echo "Log directory: $LOG_DIR"
echo ""

PING_SCRIPT="$SCRIPTS_DIR/${OPERATOR}-ping.sh"
SERVICE_NAME="${OPERATOR}-ping"
LOG_FILE="$LOG_DIR/${OPERATOR}_ping_monitor.log"

# ----------------------------
# Create ping script
# ----------------------------
cat > "$PING_SCRIPT" <<EOF
#!/bin/bash

COUNT=5
TIMEOUT=3
INTERVAL=20

HOSTS=(
$(printf "    %s\n" "${HOSTS[@]}")
)

LOG_DIR="$HOME/scripts/logs"
LOG_FILE="$LOG_DIR/${OPERATOR}_ping_monitor.log"

mkdir -p "$LOG_DIR"

echo "Starting ${OPERATOR} ping monitor"
echo "Logging to $LOG_FILE"

while true; do

    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    for HOST in "${HOSTS[@]}"; do

        OUTPUT=$(ping -c $COUNT -W $TIMEOUT -q "$HOST" 2>&1)
        STATUS=$?

        if [ $STATUS -ne 0 ]; then
            echo "$TIMESTAMP | ERROR | $HOST | Ping failed (DNS or unreachable)" >> "$LOG_FILE"
            continue
        fi

        PACKETLOSS=$(echo "$OUTPUT" | grep -oP '\d+(?=% packet loss)')
        AVG_LATENCY=$(echo "$OUTPUT" | awk -F'/' '/rtt/ {print $5}')

        if [ -z "$PACKETLOSS" ]; then
            echo "$TIMESTAMP | ERROR | $HOST | Could not parse packet loss" >> "$LOG_FILE"
            continue
        fi

        echo "$TIMESTAMP | OK | $HOST | Packet loss: ${PACKETLOSS}% | Avg Latency: ${AVG_LATENCY} ms" >> "$LOG_FILE"

    done

    sleep $INTERVAL

done
EOF

chmod +x "$PING_SCRIPT"

# ----------------------------
# Create systemd service
# ----------------------------
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=${OPERATOR^} Ping Monitor
After=network.target

[Service]
ExecStart=$PING_SCRIPT
Restart=always
RestartSec=5
User=$(whoami)
WorkingDirectory=$SCRIPTS_DIR
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

# ----------------------------
# Setup logrotate
# ----------------------------
LOGROTATE_FILE="/etc/logrotate.d/${SERVICE_NAME}"

sudo tee "$LOGROTATE_FILE" > /dev/null <<EOF
$LOG_FILE {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su $(whoami) $(whoami)
}
EOF

# ----------------------------
# Enable + Start service
# ----------------------------
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}
sudo systemctl restart ${SERVICE_NAME}

echo ""
echo "========================================"
echo " Setup Complete for Operator: $OPERATOR"
echo "========================================"
echo ""

sudo systemctl status ${SERVICE_NAME} --no-pager

echo ""
echo "Logrotate status:"
systemctl status logrotate.timer --no-pager

echo ""
echo "Logs directory:"
ls -lh "$LOG_DIR"
