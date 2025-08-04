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
# New: download Elecard ZIP via HTTP from your Nginx host
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
