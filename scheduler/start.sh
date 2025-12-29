#!/bin/sh
# Railway-compatible start script for scheduler

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"

# Function to build if dist doesn't exist
build_if_needed() {
    local dir=$1
    if [ ! -f "$dir/dist/index.js" ] && [ -f "$dir/package.json" ]; then
        echo "Building TypeScript in $dir..."
        cd "$dir"
        npm run build
        cd - > /dev/null
    fi
}

# Try multiple possible locations for dist/index.js
if [ -f "$SCRIPT_DIR/dist/index.js" ]; then
    # Running from scheduler directory
    cd "$SCRIPT_DIR"
    node dist/index.js
elif [ -f "/app/scheduler/dist/index.js" ]; then
    # Running from Railway root
    cd /app/scheduler
    node dist/index.js
elif [ -f "/app/dist/index.js" ]; then
    # Running from /app (Dockerfile context)
    cd /app
    node dist/index.js
elif [ -f "./dist/index.js" ]; then
    # Current directory has dist
    node dist/index.js
else
    # Try to build in common locations
    echo "dist/index.js not found, attempting to build..."
    build_if_needed "$SCRIPT_DIR"
    build_if_needed "/app/scheduler"
    build_if_needed "/app"
    build_if_needed "."
    
    # Try again after building
    if [ -f "$SCRIPT_DIR/dist/index.js" ]; then
        cd "$SCRIPT_DIR"
        node dist/index.js
    elif [ -f "/app/scheduler/dist/index.js" ]; then
        cd /app/scheduler
        node dist/index.js
    elif [ -f "/app/dist/index.js" ]; then
        cd /app
        node dist/index.js
    elif [ -f "./dist/index.js" ]; then
        node dist/index.js
    else
        echo "Error: Cannot find dist/index.js after build attempt"
        echo "Current directory: $(pwd)"
        echo "Script directory: $SCRIPT_DIR"
        echo "Looking for:"
        echo "  - $SCRIPT_DIR/dist/index.js"
        echo "  - /app/scheduler/dist/index.js"
        echo "  - /app/dist/index.js"
        echo "  - ./dist/index.js"
        exit 1
    fi
fi

