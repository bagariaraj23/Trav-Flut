#!/bin/bash
# Setup script for test database
# Creates the test database if it doesn't exist

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Setting up test database...${NC}"

# Load .env.test (Vitest maps TEST_DATABASE_URL → DATABASE_URL at runtime; Prisma CLI needs DATABASE_URL)
if [ -f .env.test ]; then
  set -a
  # shellcheck disable=SC1091
  source .env.test
  set +a
else
  echo -e "${RED}Error: .env.test file not found${NC}"
  echo "Copy .env.test.example to .env.test and set TEST_DATABASE_URL"
  exit 1
fi

if [ -n "$TEST_DATABASE_URL" ]; then
  export DATABASE_URL="$TEST_DATABASE_URL"
fi

if [ -z "$DATABASE_URL" ]; then
  echo -e "${RED}Error: Set TEST_DATABASE_URL or DATABASE_URL in .env.test${NC}"
  exit 1
fi

# Extract database name from URL
# Format: postgresql://user:password@host:port/database
DB_NAME=$(echo $DATABASE_URL | sed -n 's/.*\/\([^?]*\).*/\1/p')

if [ -z "$DB_NAME" ]; then
  echo -e "${RED}Error: Could not extract database name from DATABASE_URL${NC}"
  exit 1
fi

echo -e "Database name: ${DB_NAME}"

case "${DB_NAME}" in
*_test) ;;
*)
  echo -e "${RED}Refusing to touch '${DB_NAME}': only databases whose names end with _test are allowed (e.g. tripthread_test).${NC}"
  exit 1
  ;;
esac

# Extract connection info for admin connection (connect to 'postgres' database)
ADMIN_URL=$(echo $DATABASE_URL | sed "s|/${DB_NAME}|/postgres|")

# Check if database exists
DB_EXISTS=$(psql "$ADMIN_URL" -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null || echo "")

if [ "$DB_EXISTS" = "1" ]; then
  echo -e "${GREEN}✓ Database '$DB_NAME' already exists${NC}"
else
  echo -e "${YELLOW}Creating database '$DB_NAME'...${NC}"
  if psql "$ADMIN_URL" -c "CREATE DATABASE \"$DB_NAME\";" 2>/dev/null; then
    echo -e "${GREEN}✓ Database '$DB_NAME' created successfully${NC}"
  else
    echo -e "${RED}✗ Failed to create database '$DB_NAME'${NC}"
    echo "Make sure PostgreSQL is running and you have CREATE DATABASE permissions"
    exit 1
  fi
fi

# Push Prisma schema to test database
echo -e "${YELLOW}Pushing Prisma schema to test database...${NC}"
export DATABASE_URL
if ! npx prisma db push --skip-generate; then
  echo -e "${RED}✗ prisma db push failed${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Test database setup complete!${NC}"

