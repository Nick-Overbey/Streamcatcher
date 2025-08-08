#!/usr/bin/env bash
set -Eeuo pipefail

LOG_PREFIX="[install_streamcatcher]"
log()  { echo "${LOG_PREFIX} $*"; }
warn() { echo "${LOG_PREFIX} WARN: $*" >&2; }
errtrap() { echo "${LOG_PREFIX} ERROR on line $LINENO: $BASH_COMMAND" >&2; }
trap errtrap ERR

# Ensure a command exists
require_cmd() { command -v "$1" &>/dev/null; }

# Run as root (uses sudo if needed)
as_root() {
  if [ "$(id -u)" -ne 0 ] && require_cmd sudo; then
    sudo "$@"
  else
    "$@"
  fi
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
      return 1
    fi
  fi
}

# ------------------------------------------------------------------
# Begin setup
# ------------------------------------------------------------------
USER_HOME="${HOME}"
SCRIPTS_DIR="${USER_HOME}/scripts"
ELECARD_DIR="${USER_HOME}/elecard"

log "Creating required directories."
mkdir -p "${SCRIPTS_DIR}" "${ELECARD_DIR}"

# ------------------------------------------------------------------
# Optional: Configure a "jump" interface with 10.2.2.2/24 (no gateway)
#   - Auto-picks highest-index physical NIC
#   - Skips if only one non-loopback physical NIC is detected
#   - Best-effort: failures won't abort the install
#   - Override iface: JUMP_IFACE=enp7s0 ./install_streamcatcher.sh
#   - Skip entirely:  SKIP_JUMP_CONFIG=1 ./install_streamcatcher.sh
# ------------------------------------------------------------------
if [ "${SKIP_JUMP_CONFIG:-0}" != "1" ]; then
  # Helpers to list/choose candidate NICs
  list_phys_ifaces() {
    # Needs `ip`
    require_cmd ip || return 0
    ip -o link show \
    | awk -F': ' '{print $1" "$2}' \
    | sed 's/://g' \
    | awk '$2 !~ /^(lo|docker.*|veth.*|br-.*|virbr.*|vmnet.*|tailscale.*|wg.*|tun.*|tap.*|wlan.*|wl.*|sit.*|ip6tnl.*|gre.*|gretap.*|erspan.*|vlan.*|bond.*|team.*|bridge.*)$/ {print}' \
    | awk '$2 ~ /^(enp|ens|eth|eno)/ {print}' \
    | sort -k1,1n
  }

  count_phys_ifaces() {
    list_phys_ifaces | wc -l | tr -d ' '
  }

  pick_jump_iface() {
    # User override?
    if [ -n "${JUMP_IFACE:-}" ]; then
      echo "$JUMP_IFACE"
      return
    fi
    # Highest-index by kernel index (first column)
    list_phys_ifaces | tail -n1 | awk '{print $2}'
  }

  # If we can't see `ip`, don't block the install
  if ! require_cmd ip; then
    warn "'ip' command not found; skipping jump interface auto-config."
  else
    nic_count="$(count_phys_ifaces)"
    if [ "${nic_count}" -lt 2 ]; then
      log "Only ${nic_count} non-loopback physical NIC detected — skipping jump interface configuration."
    else
      log "Detected ${nic_count} physical NICs; proceeding to configure jump interface with 10.2.2.2/24 (no gateway)."

      configure_jump_iface() {
        local target_iface
        target_iface="$(pick_jump_iface || true)"
        if [ -z "${target_iface}" ]; then
          warn "Could not auto-detect a suitable interface. Set JUMP_IFACE explicitly or SKIP_JUMP_CONFIG=1."
          return 0
        fi
        log "Chosen jump interface: ${target_iface}"

        # Runtime config first (non-fatal)
        if ! ip -o addr show dev "${target_iface}" | grep -q '10\.2\.2\.2/24'; then
          log "Bringing up ${target_iface} with 10.2.2.2/24 (runtime)."
          as_root ip link set "${target_iface}" up || true
          as_root ip addr add 10.2.2.2/24 dev "${target_iface}" || true
        fi

        # Persist config via Netplan if available
        if require_cmd netplan || [ -d /etc/netplan ]; then
          local np_file="/etc/netplan/99-jump-${target_iface}.yaml"
          log "Writing Netplan at ${np_file}"
          read -r -d '' NP_YAML <<YAML
network:
  version: 2
  ethernets:
    ${target_iface}:
      dhcp4: no
      addresses:
        - 10.2.2.2/24
YAML
          printf "%s\n" "$NP_YAML" | as_root tee "$np_file" >/dev/null || true
          as_root chmod 644 "$np_file" || true
          log "Applying Netplan (best effort)."
          as_root netplan apply || warn "netplan apply failed; runtime config still set."
          return 0
        fi

        # Persist via ifupdown if present
        if [ -d /etc/network ]; then
          local if_dir="/etc/network/interfaces.d"
          local if_file="${if_dir}/${target_iface}"
          as_root mkdir -p "$if_dir" || true
          read -r -d '' IF_STANZA <<IFACE
auto ${target_iface}
allow-hotplug ${target_iface}
iface ${target_iface} inet static
    address 10.2.2.2
    netmask 255.255.255.0
    # no gateway on purpose
IFACE
          printf "%s\n" "$IF_STANZA" | as_root tee "$if_file" >/dev/null || true
          as_root chmod 644 "$if_file" || true
          # Best-effort restart
          as_root systemctl restart networking || {
            as_root ifdown "${target_iface}" 2>/dev/null || true
            as_root ifup "${target_iface}" 2>/dev/null || true
          }
          return 0
        fi

        warn "No Netplan or ifupdown config path found; runtime IP was set but not persisted."
      }

      # Never fail the whole install because of NIC config
      configure_jump_iface || warn "Jump interface configuration failed; continuing."
    fi
  fi
else
  log "Skipping jump interface configuration (SKIP_JUMP_CONFIG=1)."
fi

# ------------------------------------------------------------------
# Download GitHub scripts
# ------------------------------------------------------------------
declare -A GITHUB_FILES=(
  ["check-channels"]="https://raw.githubusercontent.com/Nick-Overbey/Streamcatcher/refs/heads/main/check-channels"
  ["baseline-tester.sh"]="https://raw.githubusercontent.com/Nick-Overbey/Streamcatcher/refs/heads/main/baseline-tester.sh"
)

# Ensure we have at least one fetch tool
if ! require_cmd curl && ! require_cmd wget; then
  apt_install_if_missing curl || apt_install_if_missing wget || {
    echo "${LOG_PREFIX} ERROR: neither curl nor wget available and installation failed." >&2
    exit 1
  }
fi

for fname in "${!GITHUB_FILES[@]}"; do
  url="${GITHUB_FILES[$fname]}"
  dest="${SCRIPTS_DIR}/${fname}"
  log "Fetching ${fname} from ${url}"
  if require_cmd curl; then
    curl -fsSL "${url}" -o "${dest}"
  else
    wget -qO "${dest}" "${url}"
  fi
  chmod +x "${dest}"
  log "Downloaded and made executable: ${dest}"
done

# ------------------------------------------------------------------
# Ensure unzip is available
# ------------------------------------------------------------------
apt_install_if_missing unzip

# ------------------------------------------------------------------
# Download Elecard ZIP via HTTP from your Nginx host
# Allow override with ELECARD_URL env var
# ------------------------------------------------------------------
ELECARD_ZIPNAME="Boro.2.2.5.2025.05.15.proj2141.zip"
ELECARD_ZIP="${ELECARD_DIR}/${ELECARD_ZIPNAME}"
ELECARD_URL_DEFAULT="http://indianlake.synology.me:49723/${ELECARD_ZIPNAME}"
ELECARD_URL="${ELECARD_URL:-$ELECARD_URL_DEFAULT}"

log "Downloading Elecard ZIP from ${ELECARD_URL}"
if require_cmd curl; then
  curl -fsSL "${ELECARD_URL}" -o "${ELECARD_ZIP}"
else
  wget -qO "${ELECARD_ZIP}" "${ELECARD_URL}"
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

as_root unzip -o "${ELECARD_ZIP}" -d "${ELECARD_DIR}"
rm -f "${ELECARD_ZIP}"
log "Elecard extraction complete."

log "Install script finished successfully."
