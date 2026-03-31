#!/usr/bin/env bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)." >&2
  exit 1
fi

TARGET_DIR="/opt/homelab/doco-cd"
COMPOSE_URL="https://raw.githubusercontent.com/newice/docker-gitops-bootstrap/main/doco-cd/compose.yaml"
ENV_FILE="$TARGET_DIR/.env"

# --- Helper functions ---

generate_secret() {
  openssl rand -hex 32
}

# Source existing .env file to preserve secrets across re-runs
load_existing_env() {
  if [[ -f "$ENV_FILE" ]]; then
    echo "Existing .env found, preserving secrets..."
    # Read values from existing .env (skip comments and empty lines)
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
      key=$(echo "$key" | xargs)
      value=$(echo "$value" | xargs)
      export "EXISTING_$key=$value"
    done < "$ENV_FILE"
  fi
}

# --- Parse arguments ---

usage() {
  echo "Usage: $0 [--token <GIT_ACCESS_TOKEN>]"
  echo ""
  echo "Options:"
  echo "  --token    GitHub personal access token for doco-cd"
  echo ""
  echo "If not provided, the script will prompt for the token on first run."
  echo "On subsequent runs, the existing token is preserved unless --token is given."
  exit 1
}

ARG_TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)
      ARG_TOKEN="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# --- Main ---

if [[ -d "$TARGET_DIR" ]]; then
  echo "==> Target directory exists, running in update mode..."
else
  echo "==> Creating target directory..."
  mkdir -p "$TARGET_DIR"
fi

echo "==> Downloading compose.yaml..."
curl -fsSL "$COMPOSE_URL" -o "$TARGET_DIR/compose.yaml"

cd "$TARGET_DIR"

# Load any existing .env values
load_existing_env

# Determine GIT_ACCESS_TOKEN: argument > existing > prompt
if [[ -n "$ARG_TOKEN" ]]; then
  GIT_ACCESS_TOKEN="$ARG_TOKEN"
elif [[ -n "${EXISTING_GIT_ACCESS_TOKEN:-}" ]]; then
  GIT_ACCESS_TOKEN="$EXISTING_GIT_ACCESS_TOKEN"
else
  read -rp "Enter your GitHub access token: " GIT_ACCESS_TOKEN < /dev/tty
  if [[ -z "$GIT_ACCESS_TOKEN" ]]; then
    echo "Error: GIT_ACCESS_TOKEN is required." >&2
    exit 1
  fi
fi

# Preserve or generate WEBHOOK_SECRET
if [[ -n "${EXISTING_WEBHOOK_SECRET:-}" ]]; then
  WEBHOOK_SECRET="$EXISTING_WEBHOOK_SECRET"
  echo "==> Reusing existing WEBHOOK_SECRET."
else
  WEBHOOK_SECRET=$(generate_secret)
  echo "==> Generated new WEBHOOK_SECRET."
fi

# Preserve optional settings from existing .env or use defaults
TZ="${EXISTING_TZ:-Europe/Berlin}"
DATA_PATH="${EXISTING_DATA_PATH:-.}"
LOG_LEVEL="${EXISTING_LOG_LEVEL:-info}"

echo "==> Writing .env file..."
cat > "$ENV_FILE" <<EOF
# Core settings
TZ=$TZ
GIT_ACCESS_TOKEN=$GIT_ACCESS_TOKEN
WEBHOOK_SECRET=$WEBHOOK_SECRET

# Optional
DATA_PATH=$DATA_PATH
LOG_LEVEL=$LOG_LEVEL
EOF

echo "==> Pulling latest images..."
docker compose pull

echo "==> Starting stack..."
docker compose up -d --remove-orphans

echo "==> Done. doco-cd is running at http://$(hostname -I | awk '{print $1}'):8000"
echo "==> GitHub webhook configuration:"
echo "    Payload URL: http://<your-ip>:8000"
echo "    Content type: application/json"
echo "    Secret:       $WEBHOOK_SECRET"
echo ""
echo "==> Add the webhook secret to your repo at:"
echo "    https://github.com/<repo>/settings/secrets/actions"