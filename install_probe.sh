#!/bin/bash

set -e

# ==========================
# Setup Directories
# ==========================
BASE_DIR="$HOME/scripts"
LOG_DIR="$BASE_DIR/logs"
ELECARD_DIR="$HOME/elecard"

mkdir -p "$BASE_DIR" "$LOG_DIR" "$ELECARD_DIR"

echo "Directories created:"
echo " - $BASE_DIR"
echo " - $LOG_DIR"
echo " - $ELECARD_DIR"
echo ""

# ==========================
# User Input
# ==========================
read -p "Enter company name: " COMPANY

echo ""
read -p "How many ping points do you want? " COUNT

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -le 0 ]; then
    echo "Invalid number. Exiting."
    exit 1
fi

HOSTS=()
for ((i=1; i<=COUNT; i++)); do
    read -p "Enter URL/IP for host #$i: " HOST
    HOSTS+=("$HOST")
done

echo ""
echo "Checking dependencies..."

# ==========================
# Install Function
# ==========================
install_pkg () {
    if command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y "$1"
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y "$1"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$1"
    else
        echo "Unsupported package manager. Install $1 manually."
        exit 1
    fi
}

command -v mtr >/dev/null || install_pkg mtr
command -v unzip >/dev/null || install_pkg unzip

if command -v curl >/dev/null; then
    DL_CMD="curl -L -o"
elif command -v wget >/dev/null; then
    DL_CMD="wget -O"
else
    install_pkg curl
    DL_CMD="curl -L -o"
fi

echo "Dependencies ready."
echo ""

# ==========================
# Download Elecard
# ==========================
ELECARD_URL="http://indianlake.synology.me:49723/Boro.2.2.7.2025.09.30.proj2141.zip"
ELECARD_ZIP="$ELECARD_DIR/elecard_probe.zip"

echo "Downloading Elecard Probe..."
$DL_CMD "$ELECARD_ZIP" "$ELECARD_URL"

echo "Extracting..."
unzip -o "$ELECARD_ZIP" -d "$ELECARD_DIR"

chmod +x "$ELECARD_DIR/lin64/"*

# ==========================
# Configure Elecard
# ==========================
CFG_FILE="$ELECARD_DIR/lin64/monitor.cfg"

if [ -f "$CFG_FILE" ]; then
    sed -i "s/\"AppDescription\": \".*\"/\"AppDescription\": \"$COMPANY\"/" "$CFG_FILE"
else
    cat <<EOF > "$CFG_FILE"
{"config": {
  "AppDescription": "$COMPANY",
  "server": "https://api.boro.elecard.com",
  "allowDownloadPcapDump": false
}}
EOF
fi

echo "Elecard configured."
echo ""

# ==========================
# Build HOST Array
# ==========================
HOST_ARRAY=$(printf '    "%s"\n' "${HOSTS[@]}")

# ==========================
# Ping Script
# ==========================
PING_SCRIPT="$BASE_DIR/ping_monitor.sh"

cat <<EOF > "$PING_SCRIPT"
#!/bin/bash
COUNT=5
TIMEOUT=3
INTERVAL=10

HOSTS=(
$HOST_ARRAY)

LOG_DIR="\$HOME/scripts/logs"
LOG_FILE="\$LOG_DIR/ping_monitor.log"

mkdir -p "\$LOG_DIR"

while true; do
    TIMESTAMP=\$(date "+%Y-%m-%d %H:%M:%S")
    for HOST in "\${HOSTS[@]}"; do
        OUTPUT=\$(ping -c \$COUNT -W \$TIMEOUT -q "\$HOST" 2>&1)
        STATUS=\$?

        if [ \$STATUS -ne 0 ]; then
            echo "\$TIMESTAMP | \$HOST | Ping failed" >> "\$LOG_FILE"
            continue
        fi

        PACKETLOSS=\$(echo "\$OUTPUT" | grep -oP '\\d+(?=% packet loss)')
        AVG_LATENCY=\$(echo "\$OUTPUT" | awk -F'/' '/rtt/ {print \$5}')

        echo "\$TIMESTAMP | \$HOST | Packet loss: \${PACKETLOSS}% | Avg Latency: \${AVG_LATENCY} ms" >> "\$LOG_FILE"
    done
    sleep \$INTERVAL
done
EOF

# ==========================
# MTR Script
# ==========================
MTR_SCRIPT="$BASE_DIR/mtr_monitor.sh"

cat <<EOF > "$MTR_SCRIPT"
#!/bin/bash
LOG_DIR="\$HOME/scripts/logs"
LOG_FILE="\$LOG_DIR/mtr.log"

TARGETS=(
$HOST_ARRAY)

CYCLES=30
INTERVAL=300

mkdir -p "\$LOG_DIR"

while true; do
  echo "===== \$(date "+%Y-%m-%d %H:%M:%S") MTR START =====" >> "\$LOG_FILE"
  for TARGET in "\${TARGETS[@]}"; do
    /usr/bin/mtr -ezbw -r -c \$CYCLES "\$TARGET" >> "\$LOG_FILE" 2>&1
  done
  echo "===== \$(date "+%Y-%m-%d %H:%M:%S") MTR END =====" >> "\$LOG_FILE"
  sleep \$INTERVAL
done
EOF

chmod +x "$PING_SCRIPT" "$MTR_SCRIPT"

# ==========================
# systemd Services
# ==========================
sudo tee /etc/systemd/system/ping-monitor.service > /dev/null <<EOF
[Unit]
Description=Ping Monitor
After=network.target
[Service]
ExecStart=$PING_SCRIPT
Restart=always
User=$USER
[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/mtr-monitor.service > /dev/null <<EOF
[Unit]
Description=MTR Monitor
After=network.target
[Service]
ExecStart=$MTR_SCRIPT
Restart=always
User=$USER
[Install]
WantedBy=multi-user.target
EOF

ELECARD_PATH="$HOME/elecard/lin64"

sudo tee /etc/systemd/system/elecard-monitor.service > /dev/null <<EOF
[Unit]
Description=Elecard Stream Monitor
After=network.target
[Service]
WorkingDirectory=$ELECARD_PATH
ExecStart=$ELECARD_PATH/streamMonitor
Restart=always
RestartSec=10
User=root
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload

sudo systemctl enable ping-monitor mtr-monitor elecard-monitor
sudo systemctl start ping-monitor mtr-monitor elecard-monitor

# ==========================
# logrotate
# ==========================
sudo tee /etc/logrotate.d/probe-monitor > /dev/null <<EOF
$LOG_DIR/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

# ==========================
# README
# ==========================
README_FILE="$HOME/PROBE_README.txt"

cat <<EOF > "$README_FILE"
========================================
        PROBE SYSTEM README
========================================

Company: $COMPANY
Install Date: $(date)

Services:
  ping-monitor
  mtr-monitor
  elecard-monitor

Check status:
  systemctl status ping-monitor
  systemctl status mtr-monitor
  systemctl status elecard-monitor

Start:
  sudo systemctl start ping-monitor mtr-monitor elecard-monitor

Stop:
  sudo systemctl stop ping-monitor mtr-monitor elecard-monitor

Restart:
  sudo systemctl restart ping-monitor mtr-monitor elecard-monitor

Logs:
  $HOME/scripts/logs/

Elecard process:
  pgrep -af streamMonitor

Live logs:
  journalctl -u elecard-monitor -f
EOF

# ==========================
# Done
# ==========================
echo ""
echo "=================================="
echo " INSTALL COMPLETE"
echo "=================================="
echo "Company: $COMPANY"
echo "README: $README_FILE"
echo ""
echo "Verify:"
echo "  systemctl status elecard-monitor"
echo "  pgrep -af streamMonitor"
echo ""
