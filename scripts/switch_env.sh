#!/bin/bash

# TripThread Backend Environment Switcher
# Usage: ./scripts/switch_env.sh [local|network|staging|production]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

# Default to local if no argument provided
ENVIRONMENT=${1:-local}

echo "🔄 Switching TripThread backend environment to: $ENVIRONMENT"

# Function to update or add a variable in .env file
update_env_var() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    # Create file if it doesn't exist
    if [ ! -f "$file" ]; then
        touch "$file"
    fi
    
    # Check if the variable exists in the file
    if grep -q "^${key}=" "$file"; then
        # Update existing variable
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$file"
        rm -f "${file}.bak"
    else
        # Add new variable
        echo "${key}=${value}" >> "$file"
    fi
}

case $ENVIRONMENT in
  "local")
    # Update only server and CORS related variables
    update_env_var "$ENV_FILE" "NEXT_PUBLIC_API_BASE_URL" "http://localhost:3000/api"
    update_env_var "$ENV_FILE" "API_BASE_URL" "http://localhost:3000/api"
    update_env_var "$ENV_FILE" "NODE_ENV" "development"
    update_env_var "$ENV_FILE" "ALLOWED_ORIGINS" "http://localhost:3000,http://localhost:3001,http://127.0.0.1:3000,http://127.0.0.1:3001"
    update_env_var "$ENV_FILE" "APP_RESET_WEB_URL" "http://$IP_ADDRESS:3000/forgot-password"

    echo "✅ Switched to local environment (localhost:3000)"
    ;;
    
  "network")
    read -p "Enter your local IP address: " IP_ADDRESS
    
    # Update only server and CORS related variables
    update_env_var "$ENV_FILE" "NEXT_PUBLIC_API_BASE_URL" "http://$IP_ADDRESS:3000/api"
    update_env_var "$ENV_FILE" "API_BASE_URL" "http://$IP_ADDRESS:3000/api"
    update_env_var "$ENV_FILE" "NODE_ENV" "development"
    update_env_var "$ENV_FILE" "ALLOWED_ORIGINS" "http://$IP_ADDRESS:3000,http://$IP_ADDRESS:3001,http://localhost:3000,http://localhost:3001,http://127.0.0.1:3000,http://127.0.0.1:3001"
    update_env_var "$ENV_FILE" "APP_RESET_WEB_URL" "http://$IP_ADDRESS:3000/forgot-password"

    echo "✅ Switched to network environment ($IP_ADDRESS:3000)"
    ;;
    
  "staging")
    # Update only server and CORS related variables
    update_env_var "$ENV_FILE" "NEXT_PUBLIC_API_BASE_URL" "https://staging-api.tripthread.com/api"
    update_env_var "$ENV_FILE" "API_BASE_URL" "https://staging-api.tripthread.com/api"
    update_env_var "$ENV_FILE" "NODE_ENV" "staging"
    update_env_var "$ENV_FILE" "ALLOWED_ORIGINS" "https://staging.tripthread.com,https://staging-api.tripthread.com"
    update_env_var "$ENV_FILE" "APP_RESET_WEB_URL" "http://$IP_ADDRESS:3000/forgot-password"

    echo "✅ Switched to staging environment"
    ;;
    
  "production")
    # Update only server and CORS related variables
    update_env_var "$ENV_FILE" "NEXT_PUBLIC_API_BASE_URL" "https://api.tripthread.com/api"
    update_env_var "$ENV_FILE" "API_BASE_URL" "https://api.tripthread.com/api"
    update_env_var "$ENV_FILE" "NODE_ENV" "production"
    update_env_var "$ENV_FILE" "ALLOWED_ORIGINS" "https://tripthread.com,https://api.tripthread.com"
    update_env_var "$ENV_FILE" "APP_RESET_WEB_URL" "http://$IP_ADDRESS:3000/forgot-password"

    echo "✅ Switched to production environment"
    ;;
    
  *)
    echo "❌ Invalid environment: $ENVIRONMENT"
    echo "Available options: local, network, staging, production"
    exit 1
    ;;
esac

echo ""
echo "📋 Backend configuration (updated variables only):"
grep -E "^(NEXT_PUBLIC_API_BASE_URL|API_BASE_URL|NODE_ENV|ALLOWED_ORIGINS|APP_RESET_WEB_URL)=" "$ENV_FILE" || echo "No matching variables found"
echo ""
echo "🔄 Restart your Next.js server for changes to take effect"
