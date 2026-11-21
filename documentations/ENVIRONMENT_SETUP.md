# Environment Configuration Setup

This document explains how to configure environment variables for both the TripThread backend (Next.js) and mobile (Flutter) applications.

## Overview

The project now uses centralized configuration through environment variables instead of hardcoded values. This makes it easier to manage different environments (development, staging, production) and update configuration values in one place.

## Files

### Backend (Next.js)

- `.env` - Contains your actual environment variables (not committed to git)
- `src/config/env.ts` - Centralized configuration class
- `scripts/switch_env.sh` - Environment switching script

### Mobile (Flutter)

- `mobile/.env` - Contains your actual environment variables (not committed to git)
- `mobile/lib/config/app_config.dart` - Centralized configuration class
- `mobile/scripts/switch_env.sh` - Environment switching script (also updates backend)

## Docker Compose

`npm run setup:env` copies `docker.env.example` to `.env`. That file is what `docker compose up` reads.

Full stack (`docker-compose.yml`):

- `DB_SCHEMA_MODE` defaults to `migrate` (`prisma migrate deploy` when the API container starts). That includes `20261111120000_user_safety_and_conversation_creator`. Restrict, Block, and the media screens add no environment variable. Rebuild the web image to serve the new Flutter screens. `push` and `skip` are opt-ins. Do not use `push` against the Neon production branch.
- `SCHEDULER_INTERVAL_SECONDS` defaults to `300`. The scheduler script still runs once per start; Compose loops it.
- `WEB_PORT` defaults to `8080`. `WEB_API_BASE_URL` (default `http://localhost:8080/api`) and `WEB_SHARE_LINK_BASE_URL` (default `http://localhost:8080`) are baked into the Flutter web image. Rebuild the `web` service after changing them.
- `MAPBOX_ACCESS_TOKEN` is required for place search. The API boots with a placeholder when it is empty.
- `SHARE_LINK_BASE_URL` on the API defaults to `http://localhost:3000` so phone builds and the share bridge on port 3000 keep working. The web image uses its own share origin on port 8080.
- `NEXT_PUBLIC_APP_WEB_URL` is the Flutter web origin for the landing page. Log in opens `{origin}/login` and Get started opens `{origin}/signup`. Local Docker uses `http://localhost:8080`. On Railway, set the hosted Flutter origin. A process environment variable overrides the file, and Next reads it when the server starts.
- `SUPPORT_EMAIL` is the inbox for `POST /api/support`. It defaults to `bagariaraj23@gmail.com` when unset. The landing page and the settings screen do not show the address. Sending still needs `SENDGRID_API_KEY` and a verified `MAIL_FROM`. Without a key the route returns 503.
- Early access stores each email in `early_access_requests`. `FIREBASE_PROJECT_NUMBER`, `FIREBASE_TESTER_GROUP`, and `FIREBASE_SERVICE_ACCOUNT_JSON` add an Android signup to Firebase App Distribution, which emails the download. `FIREBASE_ANDROID_DOWNLOAD_URL` is included in the SendGrid note when set. iPhone requests are stored and confirmed by email. The landing ring is 500 for Android requests and 100 for iPhone requests. The hero shows how many accounts exist. None of these Firebase variables are required for the signup to be saved.
- Chip-in uses `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET`. The landing page opens Razorpay Checkout for a whole amount in rupees (10 to 10000) or dollars (1 to 500), with an optional name. Dollar orders need international payments enabled on the Razorpay account. Paid rows land in `chip_ins`. After payment the browser opens `/thanks`, then returns to the landing page. A payment that does not confirm stays on a failure message with a way back to try again. Without the keys the button explains that chip-in is not open yet.

Database-only (`docker-compose.dev.yml`) leaves the API and Flutter on the host. Use `mobile/.env` with `API_BASE_URL=http://localhost:3000/api` (or `http://10.0.2.2:3000/api` on the Android emulator). The web container does not read `mobile/.env` at runtime.

Redis stays optional. Unset `REDIS_REST_URL` and `REDIS_REST_TOKEN` and the API uses an in-memory cache. The scheduler does not use Redis.

## Required Environment Variables

### Backend Configuration

```
# Database
DATABASE_URL="postgresql://username:password@localhost:5432/tripthread"

# JWT Configuration
JWT_SECRET="your-super-secret-jwt-key-change-in-production"
JWT_REFRESH_SECRET="your-super-secret-refresh-key-change-in-production"

# Email Configuration (SendGrid)
SENDGRID_API_KEY="your-sendgrid-api-key"
FROM_EMAIL="noreply@tripthread.com"
SUPPORT_EMAIL="bagariaraj23@gmail.com"

# Android early access through Firebase App Distribution. Optional.
# FIREBASE_PROJECT_NUMBER=
# FIREBASE_TESTER_GROUP=
# FIREBASE_SERVICE_ACCOUNT_JSON=
# FIREBASE_ANDROID_DOWNLOAD_URL=
# RAZORPAY_KEY_ID=
# RAZORPAY_KEY_SECRET=

# Flutter web origin for landing-page Log in and Get started. No trailing slash.
NEXT_PUBLIC_APP_WEB_URL="http://localhost:8080"

# Server Configuration
NEXT_PUBLIC_API_BASE_URL=http://localhost:3000/api
API_BASE_URL=http://localhost:3000/api
NODE_ENV=development

# CORS Configuration
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:3001,http://127.0.0.1:3000,http://127.0.0.1:3001

# Password Reset Configuration
PASSWORD_RESET_TTL_MINUTES=15
```

### Mobile Configuration

```
# API Configuration
API_BASE_URL=http://localhost:3000/api

# Environment
ENVIRONMENT=development
```

## Setup Instructions

### Option 1: Quick Environment Switching (Recommended)

Use the provided script to quickly switch between environments. This script updates both mobile and backend configurations:

```bash
# Switch to local development
./mobile/scripts/switch_env.sh local

# Switch to network development (will prompt for IP)
./mobile/scripts/switch_env.sh network

# Switch to staging
./mobile/scripts/switch_env.sh staging

# Switch to production
./mobile/scripts/switch_env.sh production
```

### Option 2: Manual Setup

1. **Copy the example files:**

   ```bash
   # Backend
   cp .env.example .env

   # Mobile
   cp mobile/.env.example mobile/.env
   ```

2. **Edit the .env files:**

   - Update `API_BASE_URL` with your actual API server URL
   - Set `ENVIRONMENT` to your current environment
   - Configure database, JWT secrets, and other settings

### Option 3: Backend-Only Environment Switching

If you only want to update the backend environment:

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

## Example Configurations

### Local Development

**Backend (.env):**

```
DATABASE_URL="postgresql://username:password@localhost:5432/tripthread"
JWT_SECRET="your-super-secret-jwt-key-change-in-production"
JWT_REFRESH_SECRET="your-super-secret-refresh-key-change-in-production"
SENDGRID_API_KEY="your-sendgrid-api-key"
FROM_EMAIL="noreply@tripthread.com"
NEXT_PUBLIC_API_BASE_URL=http://localhost:3000/api
API_BASE_URL=http://localhost:3000/api
NODE_ENV=development
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:3001,http://127.0.0.1:3000,http://127.0.0.1:3001
PASSWORD_RESET_TTL_MINUTES=15
```

**Mobile (.env):**

```
API_BASE_URL=http://localhost:3000/api
ENVIRONMENT=development
```

### Local Network

**Backend (.env):**

```
DATABASE_URL="postgresql://username:password@localhost:5432/tripthread"
JWT_SECRET="your-super-secret-jwt-key-change-in-production"
JWT_REFRESH_SECRET="your-super-secret-refresh-key-change-in-production"
SENDGRID_API_KEY="your-sendgrid-api-key"
FROM_EMAIL="noreply@tripthread.com"
NEXT_PUBLIC_API_BASE_URL=http://10.166.170.239/api
API_BASE_URL=http://10.166.170.239/api
NODE_ENV=development
ALLOWED_ORIGINS=http://10.166.170.239,http://10.166.170.239:3001,http://localhost:3000,http://localhost:3001,http://127.0.0.1:3000,http://127.0.0.1:3001
PASSWORD_RESET_TTL_MINUTES=15
```

**Mobile (.env):**

```
API_BASE_URL=http://10.166.170.239/api
ENVIRONMENT=development
```

### Staging

**Backend (.env):**

```
DATABASE_URL="postgresql://username:password@staging-db:5432/tripthread"
JWT_SECRET="your-staging-jwt-secret"
JWT_REFRESH_SECRET="your-staging-refresh-secret"
SENDGRID_API_KEY="your-sendgrid-api-key"
FROM_EMAIL="noreply@tripthread.com"
NEXT_PUBLIC_API_BASE_URL=https://staging-api.tripthread.com/api
API_BASE_URL=https://staging-api.tripthread.com/api
NODE_ENV=staging
ALLOWED_ORIGINS=https://staging.tripthread.com,https://staging-api.tripthread.com
PASSWORD_RESET_TTL_MINUTES=15
```

**Mobile (.env):**

```
API_BASE_URL=https://staging-api.tripthread.com/api
ENVIRONMENT=staging
```

### Production

**Backend (.env):**

```
DATABASE_URL="postgresql://username:password@prod-db:5432/tripthread"
JWT_SECRET="your-production-jwt-secret"
JWT_REFRESH_SECRET="your-production-refresh-secret"
SENDGRID_API_KEY="your-sendgrid-api-key"
FROM_EMAIL="noreply@tripthread.com"
NEXT_PUBLIC_API_BASE_URL=https://api.tripthread.com/api
API_BASE_URL=https://api.tripthread.com/api
NODE_ENV=production
ALLOWED_ORIGINS=https://tripthread.com,https://api.tripthread.com
PASSWORD_RESET_TTL_MINUTES=15
```

**Mobile (.env):**

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
- **Synchronized updates**: Mobile script updates both mobile and backend configs

## Usage in Code

### Backend (Next.js)

The configuration is automatically loaded when the server starts. Services can access it like this:

```typescript
import config from "@/config/env";

// Get the base URL
const baseUrl = config.apiBaseUrl;

// Get environment
const env = config.nodeEnv;

// Get CORS origins
const allowedOrigins = config.allowedOrigins;
```

### Mobile (Flutter)

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

## Security Features

### Password Reset Security

- **Current password validation**: Users must enter their current password
- **Token invalidation**: All refresh tokens are revoked after password reset
- **Reset audit**: Each reset is stored on `password_resets` (token hash, expiry, use, IP, user agent). `security_events` keeps abuse and moderation, and a password reset stays off that log
- **Password sanitization**: Sensitive data is automatically redacted from logs

### CORS Configuration

- **Environment-specific origins**: Different allowed origins for each environment
- **Secure headers**: Proper CORS headers configured in Next.js
- **Credential support**: CORS configured to support credentials

### Logging Security

- **Automatic sanitization**: Sensitive fields are automatically redacted from logs
- **Safe logging utility**: Use `safeLog()` function for secure logging
- **No password exposure**: Passwords are never logged in plain text

## Troubleshooting

- **App won't start**: Check that the `.env` file exists and has the correct format
- **API calls failing**: Verify the `API_BASE_URL` is correct and accessible
- **Environment not loading**: Ensure configuration files are properly imported
- **CORS errors**: Check that your origin is included in `ALLOWED_ORIGINS`
- **Password reset not working**: Verify JWT secrets and email configuration

## Security Notes

- Never commit the `.env` files to version control
- The `.env.example` files are safe to commit as they contain no sensitive data
- Use different JWT secrets for different environments
- Consider using different environment files for different build configurations
- Regularly rotate JWT secrets in production
- Monitor security events through the security event logging system

