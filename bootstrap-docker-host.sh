#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="/opt/homelab/doco-cd"
COMPOSE_URL="https://raw.githubusercontent.com/docker-gitops-bootstrap/main/doco-cd/compose.yaml"
GIT_ACCESS_TOKEN="xxx" # todo: chnage to param

echo "Creating target directory..."
mkdir -p "$TARGET_DIR"

echo "Downloading compose.yaml..."
curl -fsSL "$COMPOSE_URL" -o "$TARGET_DIR/compose.yaml"

echo "Changing into directory..."
cd "$TARGET_DIR"

echo "Generating .env file..."
cat > .env <<EOF
# Core settings
#TZ=Europe/Berlin
#PUID=1000
#PGID=1000
GIT_ACCESS_TOKEN=$(GIT_ACCESS_TOKEN)
# Optional
#LOG_LEVEL=info
EOF

echo "Starting stack..."
docker compose up -d

echo "Done."
