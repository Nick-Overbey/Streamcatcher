#!/usr/bin/env bash
set -euo pipefail

# Installer for ABR video probe tooling
# - creates ~/scripts and ~/elecard
# - downloads GitHub scripts into ~/scripts and makes them executable
# - downloads Elecard package from Google Drive and unzips it

LOG_PREFIX="[install_probe]"

log() {
  echo "${LOG_PREFIX} $*"
}

# Ensure required basic tools exist: curl or wget, unzip
need_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "${LOG_PREFIX} ERROR: Required command '$1' not found."
    return 1
  fi
  return 0
}

# Try to install unzip if missing and we have sudo/apt
ensure_unzip() {
  if command -v unzip &>/dev/null; then
    return
  fi
  log "unzip not found."
  if command -v apt-get &>/dev/null; then
    if [ "$(id -u)" -eq 0 ] || command -v sudo &>/dev/null; then
      log "Attempting to install unzip via apt."
      if command -v sudo &>/dev/null && [ "$(id -u)" -ne 0 ]; then
        sudo apt-get update
        sudo apt-get install -y unzip
      else
        apt-get update
        apt-get install -y unzip
      fi
      if ! command -v unzip &>/dev/null; then
        echo "${LOG_PREFIX} ERROR: unzip installation failed. Please install unzip manually."
        exit 1
      fi
    else
      echo "${LOG_PREFIX} ERROR: unzip is required but not installed, and no sudo available to install it. Install unzip manually."
      exit 1
    fi
  else
    echo "${LOG_PREFIX} ERROR: unzip is required but not installed, and no recognized package manager found. Install unzip manually."
    exit 1
  fi
}

# Google Drive download function (handles large-file confirmation)
gdrive_download() {
  local fileid=$1
  local destination=$2

  if need_cmd curl; then
    :
  else
    echo "${LOG_PREFIX} ERROR: curl is required for Google Drive download."
    exit 1
  fi

  log "Starting download from Google Drive (id=${fileid}) to ${destination}"

  # Fetch the initial page to get confirm token
  local tmp_html
  tmp_html=$(mktemp)
  local cookie
  cookie=$(mktemp)

  # Get the confirmation token page
  curl -c "${cookie}" -s -L "https://drive.google.com/uc?export=download&id=${fileid}" -o "${tmp_html}"

  # Try to extract confirm token
  local confirm
  confirm=$(sed -n 's/.*confirm=\([0-9A-Za-z_\-]*\).*/\1/p' "${tmp_html}" | head -n1)

  if [[ -n "${confirm}" ]]; then
    log "Detected confirm token, using it to download large file."
    curl -Lb "${cookie}" -s -L "https://drive.google.com/uc?export=download&confirm=${confirm}&id=${fileid}" -o "${destination}"
  else
    log "No confirm token needed; downloading directly."
    curl -Lb "${cookie}" -s -L "https://drive.google.com/uc?export=download&id=${fileid}" -o "${destination}"
  fi

  rm -f "${tmp_html}" "${cookie}"

  if [[ ! -s "${destination}" ]]; then
    echo "${LOG_PREFIX} ERROR: Downloaded file is empty or failed."
    exit 1
  fi
  log "Downloaded Google Drive file to ${destination}"
}

# Start of main logic
USER_HOME="${HOME}"
SCRIPTS_DIR="${USER_HOME}/scripts"
ELECARD_DIR="${USER_HOME}/elecard"

# 1. Create directories
log "Creating directories if they don't exist."
mkdir -p "${SCRIPTS_DIR}"
mkdir -p "${ELECARD_DIR}"

# 2. Download GitHub scripts
declare -A GITHUB_FILES=(
  ["check-channels"]="https://raw.githubusercontent.com/Nick-Overbey/Streamcatcher/refs/heads/main/check-channels"
  ["baseline-tester.sh"]="https://raw.githubusercontent.com/Nick-Overbey/Streamcatcher/refs/heads/main/baseline-tester.sh"
)

for name in "${!GITHUB_FILES[@]}"; do
  url="${GITHUB_FILES[$name]}"
  dest="${SCRIPTS_DIR}/${name}"
  log "Downloading ${name} from GitHub to ${dest}"
  if command -v curl &>/dev/null; then
    curl -fsSL "${url}" -o "${dest}"
  elif command -v wget &>/dev/null; then
    wget -qO "${dest}" "${url}"
  else
    echo "${LOG_PREFIX} ERROR: Neither curl nor wget is available to download GitHub scripts."
    exit 1
  fi
  chmod +x "${dest}"
  log "Downloaded and made executable: ${dest}"
done

# 3. Download Elecard ZIP from Google Drive
GDRIVE_FILEID="1XVNhnOlih8i8mKJkbMzz4nkMb15eoSvF"
ELECARD_ZIP="${ELECARD_DIR}/elecard.zip"

ensure_unzip
gdrive_download "${GDRIVE_FILEID}" "${ELECARD_ZIP}"

# 4. Unzip into elecard directory
log "Unzipping ${ELECARD_ZIP} into ${ELECARD_DIR}"
unzip -o "${ELECARD_ZIP}" -d "${ELECARD_DIR}"

log "Cleaning up zip file"
rm -f "${ELECARD_ZIP}"

log "Install script completed successfully."
