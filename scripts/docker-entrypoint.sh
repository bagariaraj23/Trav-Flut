#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Starting docker-entrypoint.sh..."

# Wait for the PostgreSQL database to accept connections
if [ -n "$DATABASE_URL" ]; then
  # Strip query parameters (like ?schema=public) because pg_isready fails on non-standard parameters
  DB_URL_STRIPPED="${DATABASE_URL%%\?*}"
  echo "Checking database connectivity against $DB_URL_STRIPPED..."
  until pg_isready -d "$DB_URL_STRIPPED" > /dev/null 2>&1; do
    echo "Database is not ready yet. Waiting..."
    sleep 2
  done
  echo "Database is ready!"
else
  echo "WARNING: DATABASE_URL is not set. Skipping database readiness check."
fi

# Apply migrations / push schema
echo "Applying database schema changes..."
npx prisma db push --accept-data-loss

# Execute the CMD (passed to docker run / compose)
echo "Starting Next.js application..."
exec "$@"
