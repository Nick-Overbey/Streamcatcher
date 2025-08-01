#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[install_streamcatcher]"

log() {
  echo "${LOG_PREFIX} $*"
}

# Ensure command exists
require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "${LOG_PREFIX} ERROR: Required command '$1' not found."
    return 1
  fi
  return 0
}

# Ensure unzip is installed (try installing via apt if missing)
ensure_unzip() {
  if command -v unzip &>/dev/null; then
    return
  fi
  log "unzip not found."
  if command -v apt-get &>/dev/null; then
    if [ "$(id -u)" -eq 0 ] || command -v sudo &>/dev/null; then
      log "Attempting to install unzip via apt."
      if command -v sudo &>/dev/null && [ "$(id -u)" -ne 0 ]; then
        sudo apt-get update -y
        sudo apt-get install -y unzip
      else
        apt-get update -y
        apt-get install -y unzip
      fi
      if ! command -v unzip &>/dev/null; then
        echo "${LOG_PREFIX} ERROR: unzip installation failed. Install manually."
        exit 1
      fi
    else
      echo "${LOG_PREFIX} ERROR: unzip required but cannot install (no sudo/root). Install manually."
      exit 1
    fi
  else
    echo "${LOG_PREFIX} ERROR: Cannot install unzip automatically (no apt). Install manually."
    exit 1
  fi
}

# Google Drive download with confirmation token handling
gdrive_download() {
  local fileid=$1
  local destination=$2

  require_cmd curl || { echo "${LOG_PREFIX} curl is required."; exit 1; }

  log "Downloading Google Drive file id=${fileid} to ${destination}"
  local tmp_html
  tmp_html=$(mktemp)
  local cookie
  cookie=$(mktemp)

  curl -c "${cookie}" -s -L "https://drive.google.com/uc?export=download&id=${fileid}" -o "${tmp_html}"

  local confirm
  confirm=$(sed -n 's/.*confirm=\([0-9A-Za-z_\-]*\).*/\1/p' "${tmp_html}" | head -n1)

  if [[ -n "${confirm}" ]]; then
    log "Using confirmation token to fetch large file."
    curl -Lb "${cookie}" -s -L "https://drive.google.com/uc?export=download&confirm=${confirm}&id=${fileid}" -o "${destination}"
  else
    log "No confirmation token needed; downloading directly."
    curl -Lb "${cookie}" -s -L "https://drive.google.com/uc?export=download&id=${fileid}" -o "${destination}"
  fi

  rm -f "${tmp_html}" "${cookie}"

  if [[ ! -s "${destination}" ]]; then
    echo "${LOG_PREFIX} ERROR: Download failed or empty file at ${destination}"
    exit 1
  fi
  log "Download complete: ${destination}"
}

# Begin
USER_HOME="${HOME}"
SCRIPTS_DIR="${USER_HOME}/scripts"
ELECARD_DIR="${USER_HOME}/elecard"

log "Creating directories."
mkdir -p "${SCRIPTS_DIR}"
mkdir -p "${ELECARD_DIR}"

# Download GitHub helper scripts
declare -A GITHUB_FILES=(
  ["check-channels"]="https://raw.githubusercontent.com/Nick-Overbey/Streamcatcher/refs/heads/main/check-channels"
  ["baseline-tester.sh"]="https://raw.githubusercontent.com/Nick-Overbey/Streamcatcher/refs/heads/main/baseline-tester.sh"
)

for fname in "${!GITHUB_FILES[@]}"; do
  url="${GITHUB_FILES[$fname]}"
  dest="${SCRIPTS_DIR}/${fname}"
  log "Fetching ${fname} from GitHub."
  if command -v curl &>/dev/null; then
    curl -fsSL "${url}" -o "${dest}"
  elif command -v wget &>/dev/null; then
    wget -qO "${dest}" "${url}"
  else
    echo "${LOG_PREFIX} ERROR: Neither curl nor wget available to download ${fname}."
    exit 1
  fi
  chmod +x "${dest}"
  log "Saved and made executable: ${dest}"
done

# Download Elecard ZIP
GDRIVE_FILEID="1XVNhnOlih8i8mKJkbMzz4nkMb15eoSvF"
ELECARD_ZIP="${ELECARD_DIR}/elecard.zip"

ensure_unzip
gdrive_download "${GDRIVE_FILEID}" "${ELECARD_ZIP}"

# Extract the zip(s)
log "Extracting Elecard archive(s) in ${ELECARD_DIR}"
shopt -s nullglob
zipfiles=("${ELECARD_DIR}"/*.zip)
if [ ${#zipfiles[@]} -eq 0 ]; then
  echo "${LOG_PREFIX} ERROR: No .zip file found to extract in ${ELECARD_DIR}"
  exit 1
fi

for z in "${zipfiles[@]}"; do
  log "Unzipping ${z}"
  unzip -o "${z}" -d "${ELECARD_DIR}"
done

# Cleanup zip files
log "Removing zip file(s)"
for z in "${zipfiles[@]}"; do
  rm -f "${z}"
done

log "All done."
