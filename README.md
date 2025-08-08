# Streamcatcher / ABR Video Probe Installer

## Overview

This repo contains `install_streamcatcher.sh`, an installer for the ABR video probe / troubleshooting system. It performs the following end-to-end setup:

- Creates required working directories (`~/scripts`, `~/elecard`)
- Downloads helper scripts (`check-channels` and `baseline-tester.sh`) from the Streamcatcher GitHub repo and makes them executable
- Retrieves the Elecard ZIP package
- Validates that the downloaded file is a real ZIP (checks magic bytes)
- Extracts the Elecard package into `~/elecard`

## Requirements

The installer expects a Debian/Ubuntu-style environment with the following (it will attempt to install missing pieces via `apt` when possible):

- `curl` or `wget` (for fetching GitHub scripts)
- `unzip` (for extracting the Elecard archive)
- `sshpass` (to non-interactively SCP the Elecard ZIP from the remote host, if password auth is used)
- Network access to the source of the Elecard ZIP
