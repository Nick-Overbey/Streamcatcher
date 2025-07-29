#!/usr/bin/env bash
set -euo pipefail

### ← EDIT THESE IF NEEDED ↓
USER_TO_ADD="${SUDO_USER:-$(whoami)}"
USER_HOME="$(eval echo "~$USER_TO_ADD")"
INSTALL_DIR="$USER_HOME/dockers/n8n"
### ↑ END EDITS ↑

# 1) Ensure running as root
if [[ $EUID -ne 0 ]]; then
  echo "Please run this script with sudo or as root."
  exit 1
fi

# 2) Install Docker Engine & Compose plugin
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 3) Add your user to the 'docker' group
usermod -aG docker "$USER_TO_ADD"

# 4) Create n8n directory structure
mkdir -p "$INSTALL_DIR/db_data" "$INSTALL_DIR/n8n_data"
chown -R "$USER_TO_ADD":"$USER_TO_ADD" "$USER_HOME/dockers"

# 5) Write the .env with fixed credentials
cat > "$INSTALL_DIR/.env" <<EOF
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=anothersecurepassword
POSTGRES_DB=n8n
EOF
chown "$USER_TO_ADD":"$USER_TO_ADD" "$INSTALL_DIR/.env"

# 6) Write docker-compose.yml (no version line)
cat > "$INSTALL_DIR/docker-compose.yml" <<EOF

volumes:
  db_storage:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $INSTALL_DIR/db_data

  n8n_storage:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $INSTALL_DIR/n8n_data

services:
  postgres:
    image: postgres:16
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - TZ=US/Eastern
    volumes:
      - db_storage:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -h localhost -U \${POSTGRES_USER} -d \${POSTGRES_DB}']
      interval: 5s
      timeout: 5s
      retries: 10

  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
      - DB_POSTGRESDB_USER=\${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - TZ=US/Eastern
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_SECURE_COOKIE=false
    ports:
      - 5678:5678
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - n8n_storage:/home/node/.n8n
EOF
chown "$USER_TO_ADD":"$USER_TO_ADD" "$INSTALL_DIR/docker-compose.yml"

# 7) Launch the stack
cd "$INSTALL_DIR"
docker compose pull
docker compose up -d

cat <<MSG

✅  Streamcatcher (n8n) is installed at:
   $INSTALL_DIR

Next steps:
 • Log out & back in (or run: newgrp docker) so you can use Docker without sudo.
 • Verify with: docker ps
 • Once Postgres shows “healthy”, open your browser to http://localhost:5678

MSG
