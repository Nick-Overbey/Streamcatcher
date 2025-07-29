Streamcatcher Installer and Configuration

Repository: streamcatcher

A self-contained installer and configuration repository for Streamcatcher, deploying an n8n-based ABR testing and troubleshooting probe. This script installs Docker, Docker Compose, sets up directory structures, generates environment variables, and brings up the entire stack with a single command.

⸻

🔖 Prerequisites
	•	A Linux host (tested on Ubuntu 20.04+)
	•	A non-root user with sudo privileges (the installer will add this user to the docker group)
	•	Internet access to GitHub and Docker registries

⸻

⚙️ Configuration
	1.	Download the installer

wget -O install_streamcatcher.sh \
  https://raw.githubusercontent.com/<your-user>/streamcatcher/main/install_streamcatcher.sh
chmod +x install_streamcatcher.sh


	2.	Review defaults
	•	Script will install under ~/dockers/n8n
	•	PostgreSQL credentials are hard-coded in .env as:

POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=anothersecurepassword
POSTGRES_DB=n8n


	•	Adjust these values by editing install_streamcatcher.sh if needed before running.

⸻

🚀 Quick Install

Run as root (or via sudo):

sudo ./install_streamcatcher.sh

This will:
	1.	Install Docker Engine & Docker Compose plugin
	2.	Add your user to the docker group
	3.	Create the ~/dockers/n8n directory structure
	4.	Generate a .env file with PostgreSQL credentials
	5.	Write the docker-compose.yml (without a version: line)
	6.	Pull images and start the postgres and n8n services

Once complete, log out and back in (or run newgrp docker) to use Docker without sudo.

⸻

✅ Verification
	1.	Check Docker containers:





docker ps

You should see two running containers:
- `n8n-postgres-1` (healthy)
- `n8n-n8n-1`

2. Access n8n in your browser:

http://:5678

---

## 🛠️ Updating the Installer

To apply updates or config changes:

```bash
cd ~/dockers/n8n
# Pull latest installer if using GitHub
git pull origin main
# Rerun the installer to refresh configs
sudo ./install_streamcatcher.sh


⸻

🔑 License & Access

This repository is private. All rights reserved.
No part of this software may be used, reproduced, or modified
without the express written permission of the copyright holder.

⸻

Maintained by Nick Overbey
