# Environment Configuration Setup

This document explains how to configure environment variables for the TripThread Flutter app.

## Overview

The app now uses centralized configuration through environment variables instead of hardcoded values in multiple service files. This makes it easier to manage different environments (development, staging, production) and update configuration values in one place.

## Files

- `.env` - Contains your actual environment variables (not committed to git)
- `.env.example` - Template showing the required environment variables
- `lib/config/app_config.dart` - Centralized configuration class

## Required Environment Variables

### API Configuration

```
API_BASE_URL=http://your-api-server:port/api
```

### Environment

```
ENVIRONMENT=development
```

## Setup Instructions

1. **Copy the example file:**

   ```bash
   cp .env.example .env
   ```

2. **Edit the .env file:**

   - Update `API_BASE_URL` with your actual API server URL
   - Set `ENVIRONMENT` to your current environment

3. **Quick Environment Switching (Recommended):**

   Use the provided script to quickly switch between environments:

   ```bash
   # Switch to local development
   ./scripts/switch_env.sh local

   # Switch to network development (will prompt for IP)
   ./scripts/switch_env.sh network

   # Switch to staging
   ./scripts/switch_env.sh staging

   # Switch to production
   ./scripts/switch_env.sh production
   ```

4. **Example configurations:**

   **Local Development:**

   ```
   API_BASE_URL=http://localhost:3000/api
   ENVIRONMENT=development
   ```

   **Local Network:**

   ```
   API_BASE_URL=http://192.168.1.100:3000/api
   ENVIRONMENT=development
   ```

   **Staging:**

   ```
   API_BASE_URL=https://staging-api.tripthread.com/api
   ENVIRONMENT=staging
   ```

   **Production:**

   ```
   API_BASE_URL=https://api.tripthread.com/api
   ENVIRONMENT=production
   ```

## Benefits

- **Single source of truth**: Update the base URL in one place
- **Environment-specific configs**: Easy to switch between different environments
- **Security**: Sensitive configuration not committed to version control
- **Team collaboration**: Developers can have different local configurations
- **Deployment flexibility**: Different configs for different deployment targets

## Usage in Code

The configuration is automatically loaded when the app starts. Services can access it like this:

```dart
import 'package:tripthread/config/app_config.dart';

// Get the base URL
String baseUrl = AppConfig.apiBaseUrl;

// Get environment
String env = AppConfig.environment;

// Get timeouts
Duration timeout = AppConfig.connectTimeout;
```

## Troubleshooting

- **App won't start**: Check that the `.env` file exists and has the correct format
- **API calls failing**: Verify the `API_BASE_URL` is correct and accessible
- **Environment not loading**: Ensure `AppConfig.initialize()` is called in `main()`

## Security Notes

- Never commit the `.env` file to version control
- The `.env.example` file is safe to commit as it contains no sensitive data
- Consider using different environment files for different build configurations
