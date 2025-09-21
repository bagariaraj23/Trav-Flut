#!/bin/bash

# TripThread Environment Switcher
# Usage: ./scripts/switch_env.sh [local|network|staging|production]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

# Default to local if no argument provided
ENVIRONMENT=${1:-local}

echo "🔄 Switching TripThread environment to: $ENVIRONMENT"

case $ENVIRONMENT in
  "local")
    cat > "$ENV_FILE" << EOF
# API Configuration
API_BASE_URL=http://localhost:3000/api

# Environment
ENVIRONMENT=development
EOF
    echo "✅ Switched to local environment (localhost:3000)"
    ;;
    
  "network")
    read -p "Enter your local IP address: " IP_ADDRESS
    cat > "$ENV_FILE" << EOF
# API Configuration
API_BASE_URL=http://$IP_ADDRESS:3000/api

# Environment
ENVIRONMENT=development
EOF
    echo "✅ Switched to network environment ($IP_ADDRESS:3000)"
    ;;
    
  "staging")
    cat > "$ENV_FILE" << EOF
# API Configuration
API_BASE_URL=https://staging-api.tripthread.com/api

# Environment
ENVIRONMENT=staging
EOF
    echo "✅ Switched to staging environment"
    ;;
    
  "production")
    cat > "$ENV_FILE" << EOF
# API Configuration
API_BASE_URL=https://api.tripthread.com/api

# Environment
ENVIRONMENT=production
EOF
    echo "✅ Switched to production environment"
    ;;
    
  *)
    echo "❌ Invalid environment: $ENVIRONMENT"
    echo "Available options: local, network, staging, production"
    exit 1
    ;;
esac

echo ""
echo "📋 Current configuration:"
cat "$ENV_FILE"
echo ""
echo "🔄 Restart your Flutter app for changes to take effect"
