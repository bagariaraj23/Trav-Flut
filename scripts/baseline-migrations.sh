#!/usr/bin/env bash
# Mark every folder under prisma/migrations as already applied.
# Use only when the database schema already matches migrations but _prisma_migrations is empty/out of sync.
# Typical flow for a new machine: use `npm run db:migrate` instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "This will run: prisma migrate resolve --applied <name> for each folder in prisma/migrations/"
echo "Ensure DATABASE_URL points at the intended database."
read -r -p "Continue? [y/N] " REPLY
echo

if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

shopt -s nullglob
for dir in prisma/migrations/*/; do
  name="$(basename "$dir")"
  [[ "$name" == "migration.sql" ]] && continue
  echo "Resolving: $name"
  npx prisma migrate resolve --applied "$name"
done

echo "Baseline complete."
