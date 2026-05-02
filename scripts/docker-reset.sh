#!/usr/bin/env bash

# TripThread — stop containers and delete dev/test DB volumes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/docker-compose-cmd.sh"

COMPOSE_FILE="$REPO_ROOT/docker-compose.dev.yml"

echo "This will delete all data in the TripThread dev and test PostgreSQL volumes."
read -r -p "Continue? [y/N] " REPLY
echo

if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

echo "Stopping containers and removing volumes..."
"${DOCKER_COMPOSE_BASE[@]}" -f "$COMPOSE_FILE" down -v

echo "Starting fresh containers..."
"${DOCKER_COMPOSE_BASE[@]}" -f "$COMPOSE_FILE" up -d

echo "Waiting for databases..."
sleep 5

echo ""
echo "Reset complete. Run: npm run db:migrate && npm run db:seed (optional)"
echo ""
