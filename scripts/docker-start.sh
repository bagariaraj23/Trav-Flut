#!/usr/bin/env bash

# TripThread — start development databases (Docker Compose)
# Starts PostgreSQL for dev (5432) and test (5433). Schema is applied via Prisma (npm run db:migrate).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=docker-compose-cmd.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/docker-compose-cmd.sh"

echo "Starting TripThread development databases..."

if ! docker info > /dev/null 2>&1; then
  echo "Docker is not running. Please start Docker Desktop (or the Docker daemon) first."
  exit 1
fi

COMPOSE_FILE="$REPO_ROOT/docker-compose.dev.yml"
echo "Using: ${DOCKER_COMPOSE_BASE[*]} -f docker-compose.dev.yml up -d"
"${DOCKER_COMPOSE_BASE[@]}" -f "$COMPOSE_FILE" up -d

echo "Waiting for PostgreSQL to accept connections..."
sleep 3

echo "Container status:"
"${DOCKER_COMPOSE_BASE[@]}" -f "$COMPOSE_FILE" ps

echo ""
echo "Development databases are running."
echo ""
echo "Connection details (defaults; override with POSTGRES_* in .env for Compose):"
echo "  Dev DB:  postgresql://\${POSTGRES_USER:-postgres}:\${POSTGRES_PASSWORD:-postgres}@localhost:\${POSTGRES_PORT:-5432}/\${POSTGRES_DB:-tripthread_dev}?schema=public"
echo "  Test DB: postgresql://postgres:postgres@localhost:5433/tripthread_test?schema=public"
echo ""
echo "Next steps (from repo root, host Node — not inside a container):"
echo "  1. npm install"
echo "  2. npm run setup:env   # or: cp docker.env.example .env"
echo "  3. npm run db:generate && npm run db:migrate"
echo "  4. npm run db:seed      # optional"
echo "  5. npm run dev"
echo ""
echo "Caching: set REDIS_REST_URL + REDIS_REST_TOKEN (Upstash REST) in .env if needed; otherwise the API uses in-memory LRU cache."
echo ""
