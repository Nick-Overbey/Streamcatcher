#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[install_streamcatcher]"

log() {
  echo "${LOG_PREFIX} $*"
}

# Ensure a command exists
require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    return 1
  fi
  return 0
}

# Install a package if apt is available
apt_install_if_missing() {
  local pkg=$1
  if ! require_cmd "$pkg"; then
    if command -v apt-get &>/dev/null; then
      log "Installing ${pkg} via apt."
      if [ "$(id -u)" -ne 0 ] && command -v sudo &>/dev/null; then
        sudo apt-get update -y
        sudo sudo apt-get install -y "${pkg}"
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
mkdir -p "${SCRIPTS_DIR}"
mkdir -p "${ELECARD_DIR}"

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
if ! require_cmd unzip; then
  log "unzip missing; installing."
  if command -v apt-get &>/dev/null; then
    if [ "$(id -u)" -ne 0 ] && command -v sudo &>/dev/null; then
      sudo apt-get update -y
      sudo sudo apt-get install -y unzip
    else
      apt-get update -y
      apt-get install -y unzip
    fi
  else
    echo "${LOG_PREFIX} ERROR: cannot install unzip automatically; install manually." >&2
    exit 1
  fi
fi

# Ensure sshpass is present
if ! require_cmd sshpass; then
  log "sshpass not found; installing."
  if command -v apt-get &>/dev/null; then
    if [ "$(id -u)" -ne 0 ] && command -v sudo &>/dev/null; then
      sudo apt-get update -y
      sudo sudo apt-get install -y sshpass
    else
      apt-get update -y
      apt-get install -y sshpass
    fi
  else
    echo "${LOG_PREFIX} ERROR: cannot install sshpass automatically; install manually." >&2
    exit 1
  fi
fi

# Download Elecard ZIP from Synology via scp using sshpass
SYN_USER="elecard"
SYN_HOST="indianlake.synology.me"
SYN_PORT="2022"
SYN_REMOTE_PATH="/sftp/Boro.2.2.5.2025.05.15.proj2141.zip"
ELECARD_ZIP="${ELECARD_DIR}/Boro.2.2.5.2025.05.15.proj2141.zip"
SYN_PASSWORD="elecard25"

log "Pulling Elecard ZIP from Synology (${SYN_HOST}) via scp."
mkdir -p "${ELECARD_DIR}"

sshpass -p "${SYN_PASSWORD}" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "${SYN_PORT}" "${SYN_USER}@${SYN_HOST}:${SYN_REMOTE_PATH}" "${ELECARD_ZIP}"

if [[ ! -f "${ELECARD_ZIP}" ]]; then
  echo "${LOG_PREFIX} ERROR: failed to retrieve Elecard ZIP from Synology." >&2
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
