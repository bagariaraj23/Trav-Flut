#!/usr/bin/env bash

# TripThread — stop development database containers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/docker-compose-cmd.sh"

COMPOSE_FILE="$REPO_ROOT/docker-compose.dev.yml"

echo "Stopping TripThread development databases..."
"${DOCKER_COMPOSE_BASE[@]}" -f "$COMPOSE_FILE" down

echo "Containers stopped."
echo "To remove volumes (wipe data): ${DOCKER_COMPOSE_BASE[*]} -f docker-compose.dev.yml down -v"
echo ""
