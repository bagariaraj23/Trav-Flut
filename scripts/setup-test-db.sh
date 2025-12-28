#!/bin/bash
# Setup script for test database
# Creates the test database if it doesn't exist

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Setting up test database...${NC}"

# Load .env.test to get DATABASE_URL
if [ -f .env.test ]; then
  export $(cat .env.test | grep -v '^#' | xargs)
else
  echo -e "${RED}Error: .env.test file not found${NC}"
  echo "Please create .env.test with DATABASE_URL"
  exit 1
fi

if [ -z "$DATABASE_URL" ]; then
  echo -e "${RED}Error: DATABASE_URL not set in .env.test${NC}"
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

# Extract connection info for admin connection (connect to 'postgres' database)
ADMIN_URL=$(echo $DATABASE_URL | sed "s|/${DB_NAME}|/postgres|")

# Check if database exists
DB_EXISTS=$(psql "$ADMIN_URL" -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null || echo "")

if [ "$DB_EXISTS" = "1" ]; then
  echo -e "${GREEN}✓ Database '$DB_NAME' already exists${NC}"
else
  echo -e "${YELLOW}Creating database '$DB_NAME'...${NC}"
  psql "$ADMIN_URL" -c "CREATE DATABASE \"$DB_NAME\";" 2>/dev/null
  if [ $? -eq 0 ]; then
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
npx prisma db push --skip-generate 2>&1 | grep -v "Generated Prisma Client" || true

echo -e "${GREEN}✓ Test database setup complete!${NC}"

