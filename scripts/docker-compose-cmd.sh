#!/usr/bin/env bash
# Resolve docker compose v2 (`docker compose`) vs legacy (`docker-compose`).
# Usage: source scripts/docker-compose-cmd.sh   # sets DOCKER_COMPOSE_BASE
# Or:    scripts/docker-compose-cmd.sh          # prints the base command

if docker compose version &>/dev/null; then
  DOCKER_COMPOSE_BASE=(docker compose)
else
  DOCKER_COMPOSE_BASE=(docker-compose)
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf '%s\n' "${DOCKER_COMPOSE_BASE[*]}"
fi
