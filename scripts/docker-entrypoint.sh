#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

echo "Starting docker-entrypoint.sh..."

# Strip query parameters (like ?schema=public) because pg_isready/psql reject them
DB_URL_STRIPPED="${DATABASE_URL:+${DATABASE_URL%%\?*}}"

if [ -n "$DB_URL_STRIPPED" ]; then
  echo "Checking database connectivity against $DB_URL_STRIPPED..."
  until pg_isready -d "$DB_URL_STRIPPED" > /dev/null 2>&1; do
    echo "Database is not ready yet. Waiting..."
    sleep 2
  done
  echo "Database is ready!"
else
  echo "WARNING: DATABASE_URL is not set. Skipping database readiness check and schema apply."
  exec "$@"
fi

sql() {
  psql "$DB_URL_STRIPPED" -tAX -v ON_ERROR_STOP=1 -c "$1"
}

table_exists() {
  [ "$(sql "SELECT to_regclass('public.\"$1\"') IS NOT NULL")" = "t" ]
}

column_exists() {
  [ "$(sql "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = '$1' AND column_name = '$2')")" = "t" ]
}

# Databases created by the old entrypoint (prisma db push) have tables but no
# _prisma_migrations. Bring the schema up to date, replay data-only migration
# steps that push cannot run, then mark every migration as applied so later
# boots use migrate deploy.
baseline_pushed_database() {
  echo "Existing schema without _prisma_migrations — baselining."
  local had_type_flag=false
  if column_exists trips typeSetByUser; then
    had_type_flag=true
  fi

  npx prisma db push --skip-generate

  if [ "$had_type_flag" = false ]; then
    echo "Backfilling trips.typeSetByUser for trips that already had a type..."
    sql 'UPDATE "trips" SET "typeSetByUser" = true WHERE "type" IS NOT NULL'
  fi

  for dir in prisma/migrations/*/; do
    name="$(basename "$dir")"
    npx prisma migrate resolve --applied "$name" > /dev/null
    echo "  marked $name as applied"
  done
}

DB_SCHEMA_MODE="${DB_SCHEMA_MODE:-migrate}"
echo "Applying database schema (DB_SCHEMA_MODE=$DB_SCHEMA_MODE)..."

case "$DB_SCHEMA_MODE" in
  migrate)
    if table_exists _prisma_migrations || ! table_exists users; then
      npx prisma migrate deploy
    else
      baseline_pushed_database
      npx prisma migrate deploy
    fi
    ;;
  push)
    if [ "${ALLOW_DATA_LOSS:-0}" = "1" ]; then
      echo "WARNING: ALLOW_DATA_LOSS=1 — running prisma db push --accept-data-loss"
      npx prisma db push --skip-generate --accept-data-loss
    else
      npx prisma db push --skip-generate
    fi
    ;;
  skip)
    echo "Skipping schema apply."
    ;;
  *)
    echo "Unknown DB_SCHEMA_MODE '$DB_SCHEMA_MODE' (expected migrate, push, or skip)." >&2
    exit 1
    ;;
esac

echo "Starting: $*"
exec "$@"
