#!/usr/bin/env bash

set -euo pipefail

DEFAULT_BASE_DIR="/opt/homelab"
COMPOSE_URL="https://raw.githubusercontent.com/newice/docker-gitops-bootstrap/main/doco-cd/compose.yaml"

# --- Helper functions ---

generate_secret() {
  openssl rand -hex 32
}

require_value() {
  local option="$1"
  local value="${2:-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    echo "Error: $option requires a value." >&2
    usage
  fi
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
  local exit_code="${1:-1}"

  echo "Usage: $0 [--token <GIT_ACCESS_TOKEN>] [--base-dir <PATH>]"
  echo ""
  echo "Options:"
  echo "  --token       GitHub personal access token for doco-cd"
  echo "  --base-dir    Base directory for the doco-cd installation (default: $DEFAULT_BASE_DIR)"
  echo ""
  echo "If not provided, the script will prompt for the token on first run."
  echo "On subsequent runs, the existing token is preserved unless --token is given."
  exit "$exit_code"
}

ARG_TOKEN=""
BASE_DIR="$DEFAULT_BASE_DIR"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)
      require_value "$1" "${2:-}"
      ARG_TOKEN="$2"
      shift 2
      ;;
    --base-dir)
      require_value "$1" "${2:-}"
      BASE_DIR="$2"
      shift 2
      ;;
    --help|-h)
      usage 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

BASE_DIR="${BASE_DIR%/}"
if [[ -z "$BASE_DIR" ]]; then
  BASE_DIR="/"
fi

TARGET_DIR="${BASE_DIR%/}/doco-cd"
if [[ "$BASE_DIR" == "/" ]]; then
  TARGET_DIR="/doco-cd"
fi

ENV_FILE="$TARGET_DIR/.env"

# --- Main ---

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)." >&2
  exit 1
fi

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

# Ensure data directory exists for bind mount before first compose run
mkdir -p "$TARGET_DIR/data"

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

# Display age public key for SOPS encryption
AGE_KEY_FILE="$TARGET_DIR/data/age-keys.txt"
if [[ -f "$AGE_KEY_FILE" ]]; then
  AGE_PUBLIC_KEY=$(grep '# public key:' "$AGE_KEY_FILE" | sed 's/.*# public key: //')
  echo ""
  echo "==> SOPS/age encryption:"
  echo "    Public key: $AGE_PUBLIC_KEY"
  echo "    Use in .sops.yaml or with: sops encrypt --age $AGE_PUBLIC_KEY <file>"
fi
