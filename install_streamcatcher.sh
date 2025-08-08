#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[install_streamcatcher]"

log() {
  echo "${LOG_PREFIX} $*"
}

# Ensure a command exists
require_cmd() {
  command -v "$1" &>/dev/null
}

# Install a package if apt is available
apt_install_if_missing() {
  local pkg=$1
  if ! require_cmd "$pkg"; then
    if require_cmd apt-get; then
      log "Installing ${pkg} via apt."
      if [ "$(id -u)" -ne 0 ] && require_cmd sudo; then
        sudo apt-get update -y
        sudo apt-get install -y "${pkg}"
      else
        apt-get update -y
        apt-get install -y "${pkg}"
      fi
    else
      echo "${LOG_PREFIX} ERROR: cannot install ${pkg}; apt-get not available. Install manually." >&2
      exit 1
    fi
  fi
}

# Begin setup
USER_HOME="${HOME}"
SCRIPTS_DIR="${USER_HOME}/scripts"
ELECARD_DIR="${USER_HOME}/elecard"

log "Creating required directories."
mkdir -p "${SCRIPTS_DIR}" "${ELECARD_DIR}"

# ------------------- Configure jump interface (10.2.2.2/24, no gateway) -------------------
# If you want to force a specific iface, export JUMP_IFACE=enp7s0 before running.
log "Selecting jump interface to configure with 10.2.2.2/24 (no gateway)."

pick_jump_iface() {
  # User override?
  if [ -n "${JUMP_IFACE:-}" ]; then
    echo "$JUMP_IFACE"
    return
  fi

  # From `ip -o link`: "7: enp7s0: <...>"
  # Filter out loopback, wireless, containers, bridges, tunnels, etc.
  ip -o link show \
  | awk -F': ' '{print $1" "$2}' \
  | sed 's/://g' \
  | awk '$2 !~ /^(lo|docker.*|veth.*|br-.*|virbr.*|vmnet.*|tailscale.*|wg.*|tun.*|tap.*|wlan.*|wl.*|sit.*|ip6tnl.*|gre.*|gretap.*|erspan.*|vlan.*|bond.*|team.*|bridge.*)$/ {print}' \
  | awk '$2 ~ /^(enp|ens|eth|eno)/ {print}' \
  | sort -k1,1n \
  | tail -n1 \
  | awk '{print $2}'
}

configure_jump_iface() {
  local target_iface
  target_iface="$(pick_jump_iface || true)"

  if [ -z "${target_iface}" ]; then
    echo "${LOG_PREFIX} ERROR: Could not auto-detect a suitable interface. Set JUMP_IFACE explicitly." >&2
    exit 1
  fi

  log "Chosen jump interface: ${target_iface}"

  if require_cmd netplan || [ -d /etc/netplan ]; then
    # Netplan path
    local np_file="/etc/netplan/01-${target_iface}.yaml"

    # Backup existing
    if [ -f "$np_file" ]; then
      if [ "$(id -u)" -ne 0 ] && require_cmd sudo; then
        sudo cp -a "$np_file" "${np_file}.bak.$(date +%s)"
      else
        cp -a "$np_file" "${np_file}.bak.$(date +%s)"
      fi
    fi

    read -r -d '' NP_YAML <<YAML
network:
  version: 2
  ethernets:
    ${target_iface}:
      dhcp4: no
      addresses:
        - 10.2.2.2/24
YAML

    if [ "$(id -u)" -ne 0 ] && require_cmd sudo; then
      printf "%s\n" "$NP_YAML" | sudo tee "$np_file" >/dev/null
      sudo chmod 644 "$np_file"
      log "Applying Netplan."
      sudo netplan apply
    else
      printf "%s\n" "$NP_YAML" > "$np_file"
      chmod 644 "$np_file"
      log "Applying Netplan."
      netplan apply
    fi

  else
    # ifupdown path
    local if_dir="/etc/network/interfaces.d"
    local if_file="${if_dir}/${target_iface}"

    if [ "$(id -u)" -ne 0 ] && require_cmd sudo; then
      sudo mkdir -p "$if_dir"
    else
      mkdir -p "$if_dir"
    fi

    if [ -f "$if_file" ]; then
      if [ "$(id -u)" -ne 0 ] && require_cmd sudo; then
        sudo cp -a "$if_file" "${if_file}.bak.$(date +%s)"
      else
        cp -a "$if_file" "${if_file}.bak.$(date +%s)"
      fi
    fi

    read -r -d '' IF_STANZA <<IFACE
auto ${target_iface}
allow-hotplug ${target_iface}
iface ${target_iface} inet static
    address 10.2.2.2
    netmask 255.255.255.0
    # no gateway on purpose
IFACE

    if [ "$(id -u)" -ne 0 ] && require_cmd sudo; then
      printf "%s\n" "$IF_STANZA" | sudo tee "$if_file" >/dev/null
      sudo chmod 644 "$if_file"
      log "Restarting networking (ifupdown)."
      sudo systemctl restart networking || {
        sudo ifdown "${target_iface}" 2>/dev/null || true
        sudo ifup "${target_iface}"
      }
    else
      printf "%s\n" "$IF_STANZA" > "$if_file"
      chmod 644 "$if_file"
      log "Restarting networking (ifupdown)."
      systemctl restart networking || {
        ifdown "${target_iface}" 2>/dev/null || true
        ifup "${target_iface}"
      }
    fi
  fi
}

configure_jump_iface
# ----------------- end jump interface auto-configuration block ---------------------

# Download GitHub scripts
declare -A GITHUB_FILES=(
  ["check-channels"]="https://raw.githubusercontent.com/Nick-Overbey/Streamcatcher/refs/heads/main/check-channels"
  ["baseline-tester.sh"]="https://raw.githubusercontent.com/Nick-Overbey/Streamcatcher/refs/heads/main/baseline-tester.sh"
)

for fname in "${!GITHUB_FILES[@]}"; do
  url="${GITHUB_FILES[$fname]}"
  dest="${SCRIPTS_DIR}/${fname}"
  log "Fetching ${fname} from ${url}"
  if require_cmd curl; then
    curl -fsSL "${url}" -o "${dest}"
  elif require_cmd wget; then
    wget -qO "${dest}" "${url}"
  else
    echo "${LOG_PREFIX} ERROR: neither curl nor wget available to download ${fname}." >&2
    exit 1
  fi
  chmod +x "${dest}"
  log "Downloaded and made executable: ${dest}"
done

# Ensure unzip is available
apt_install_if_missing unzip

# ------------------------------------------------------------------
# Download Elecard ZIP via HTTP from your Nginx host
# ------------------------------------------------------------------
ELECARD_ZIP="${ELECARD_DIR}/Boro.2.2.5.2025.05.15.proj2141.zip"
ELECARD_URL="http://indianlake.synology.me:49723/Boro.2.2.5.2025.05.15.proj2141.zip"

log "Downloading Elecard ZIP from ${ELECARD_URL}"
if require_cmd curl; then
  curl -fsSL "${ELECARD_URL}" -o "${ELECARD_ZIP}"
elif require_cmd wget; then
  wget -qO "${ELECARD_ZIP}" "${ELECARD_URL}"
else
  echo "${LOG_PREFIX} ERROR: neither curl nor wget available to fetch Elecard ZIP." >&2
  exit 1
fi

if [[ ! -s "${ELECARD_ZIP}" ]]; then
  echo "${LOG_PREFIX} ERROR: download failed or empty file at ${ELECARD_ZIP}" >&2
  exit 1
fi

# Validate ZIP signature (PK\x03\x04)
if head -c4 "${ELECARD_ZIP}" | grep -q $'\x50\x4B\x03\x04'; then
  log "Elecard ZIP appears valid; extracting."
else
  echo "${LOG_PREFIX} ERROR: downloaded Elecard file is not a valid ZIP. Dumping first 512 bytes for inspection:" >&2
  head -c512 "${ELECARD_ZIP}" | sed 's/^/>> /'
  exit 1
fi

unzip -o "${ELECARD_ZIP}" -d "${ELECARD_DIR}"
rm -f "${ELECARD_ZIP}"
log "Elecard extraction complete."

log "Install script finished successfully."
