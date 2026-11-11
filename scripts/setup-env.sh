#!/usr/bin/env bash

# Create .env / .env.test from repo templates for local development (including Docker DB URLs).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "Setting up environment files..."
echo ""

if [[ -f .env ]]; then
  echo "✓ .env already exists (left unchanged)"
else
  if [[ -f docker.env.example ]]; then
    echo "Creating .env from docker.env.example ..."
    cp docker.env.example .env
    echo "✓ .env created"
  elif [[ -f .env.docker ]]; then
    echo "Creating .env from .env.docker ..."
    cp .env.docker .env
    echo "✓ .env created"
  else
    echo "⚠ docker.env.example missing; copy .env.example to .env and set DATABASE_URL."
    exit 1
  fi
  echo ""
  echo "⚠ Edit .env and set secrets: JWT_SECRET, JWT_REFRESH_SECRET, and any Cloudinary / SendGrid / Mapbox keys you need."
fi

echo ""

if [[ -f .env.test ]]; then
  echo "✓ .env.test already exists (left unchanged)"
else
  if [[ -f .env.test.example ]]; then
    echo "Creating .env.test from .env.test.example ..."
    cp .env.test.example .env.test
    echo "✓ .env.test created"
  else
    echo "Creating minimal .env.test (Docker test DB on port 5433)..."
    cat > .env.test << 'EOF'
NODE_ENV=test
TEST_DATABASE_URL="postgresql://postgres:postgres@localhost:5433/tripthread_test?schema=public"
TEST_JWT_SECRET="test-jwt-secret-key-for-testing-only"
TEST_MAPBOX_ACCESS_TOKEN="test-mapbox-token"
EOF
    echo "✓ .env.test created"
  fi
fi

echo ""
echo "Done."
echo "Next:"
echo "  1. npm run docker:start   # PostgreSQL dev + test"
echo "  2. npm run db:generate && npm run db:migrate"
echo "  3. npm run dev"
echo ""
