Probe Installer

Overview

This repository contains a one-step installer script that provisions a complete network and video monitoring probe.

The installer automates deployment of:
	•	Continuous Ping monitoring
	•	Scheduled MTR (traceroute) monitoring
	•	Elecard Stream Monitor (deep video/packet analysis)
	•	System services (systemd) with auto-start and restart
	•	Log management (logrotate)
	•	Local documentation (README generated on install)

The goal is to provide a repeatable, zero-touch deployment that can be used across multiple customer environments.

⸻

Features
	•	Fully automated installation and configuration
	•	Runs all monitoring tools as system services
	•	Survives reboots and auto-recovers from failures
	•	Centralized logging with automatic rotation
	•	Automatic dependency installation
	•	Auto-configuration of Elecard probe name
	•	Built-in operational README on deployed system

⸻

Requirements
	•	Linux system (Ubuntu/Debian, RHEL/CentOS, or Fedora-based)
	•	Internet access (for dependency install + Elecard download)
	•	User with sudo privileges

⸻

Installation

Clone the repository or copy the installer script, then run:
chmod +x install.sh
./install.sh
You will be prompted for:
	•	Company name (used for probe identification)
	•	Number of monitoring endpoints
	•	Target URLs/IPs

⸻

What Gets Installed

Directory Structure
~/scripts/
~/scripts/logs/
~/elecard/

Services
Service Name
Description
ping-monitor
Continuous ping monitoring
mtr-monitor
Periodic traceroute monitoring
elecard-monitor
Elecard streamMonitor (runs as root)

All services:
	•	Start automatically on boot
	•	Restart automatically on failure

Logs

Tool
Log File
Ping
~/scripts/logs/ping_monitor.log
MTR
~/scripts/logs/mtr.log

Logs are rotated daily and retained for 7 days.

Elecard Integration

The installer:
	•	Downloads Elecard Probe package
	•	Extracts it to: ~/elecard/
	•	Automatically updates: ~/elecard/lin64/monitor.cfg
  	•	Sets the probe name using the provided company name
	•	Runs: streamMonitor as a root-level systemd service

  Service Management

Check Status
systemctl status ping-monitor
systemctl status mtr-monitor
systemctl status elecard-monitor

Start Services
sudo systemctl start ping-monitor mtr-monitor elecard-monitor

Stop Services
sudo systemctl stop ping-monitor mtr-monitor elecard-monitor

Restart Services
sudo systemctl restart ping-monitor mtr-monitor elecard-monitor

Notes
	•	Ping runs every 10 seconds
	•	MTR runs every 5 minutes
	•	Elecard runs continuously
	•	All services are managed via systemd
	•	Logs are automatically rotated

⸻

Intended Use

This installer is designed for:
	•	Deploying probes to customer environments
	•	Troubleshooting IPTV / ABR streaming issues
	•	Monitoring CDN and network path stability
	•	Rapid field deployment with minimal configuration

⸻

Future Enhancements (Planned)
	•	Centralized probe status reporting
	•	Remote configuration management
	•	Automated alerting (packet loss / outages)
	•	Probe fleet dashboard integration
