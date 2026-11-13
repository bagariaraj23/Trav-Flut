# TripThread - Travel Social Media Platform

A social media platform for travelers to document and share their trips with friends and followers.

## 🏗️ Architecture Overview

TripThread uses a microservices architecture with the following components:

### 1. Main Application (Next.js)

- **Framework**: Next.js 15 with App Router (`server.cjs` serves REST and the chat WebSocket)
- **Language**: TypeScript
- **Database**: PostgreSQL with Prisma ORM
- **Authentication**: JWT (Access + Refresh Token)
- **Caching**: Redis (Upstash) - Two-tier caching (Memory + Redis)
- **Media Storage**: Cloudinary
- **API**: RESTful APIs with proper error handling
- **Email**: SendGrid integration

**Features:**
- RESTful API endpoints
- JWT authentication
- Redis caching (two-tier: Memory + Redis)
- Cloudinary media uploads
- Place search and management
- User management and social features

### 2. Frontend: Flutter App

- **Platform**: iOS and Android. The local Docker stack also serves a Flutter web build.
- **State Management**: Provider
- **Navigation**: GoRouter
- **Storage**: Flutter Secure Storage for JWT tokens on iOS and Android. The web build stores the session in browser local storage.
- **HTTP Client**: Dio with interceptors
- **Location Services**: Geolocator, Geocoding, and Mapbox Maps 3.34 (`mapbox_maps_flutter`). The same map and pin dropper render on iOS, Android, and the web UI.
- **Media**: Image picker, video player, Cloudinary integration

### 3. Background Job Scheduler (Independent Service)

- **Type**: Independent cron-based service
- **Purpose**: Automatically updates trip statuses (UPCOMING → ONGOING → ENDED)
- **Technology**: Node.js + TypeScript
- **Deployment**: One-shot script. Production cron (Railway, GitHub Actions, or system cron) invokes it. Local Docker loops that same script every `SCHEDULER_INTERVAL_SECONDS` (default 300) after the API is healthy.
- **Zero Redis dependency** - All Redis budget available for API caching

**Key Design Decision:** The scheduler runs as a simple script that:
- Executes once per invocation and exits
- Connects directly to PostgreSQL
- Uses zero Redis commands
- Leaves the schedule to the caller (cron, or the Compose shell loop)

For detailed scheduler architecture, see [scheduler/SCHEDULER_ARCHITECTURE.md](./scheduler/SCHEDULER_ARCHITECTURE.md).

### 4. Database: PostgreSQL

- **ORM**: Prisma
- **Schema**: User, Trip, TripThreadEntry, Place, Follow, Media, and more
- **Features**: UUID primary keys, proper relationships, spatial indexes
- **Shared**: Between main app and scheduler

### 5. Cache Layer (Redis/Upstash)

- **Two-tier caching**: Memory (L1) + Redis (L2)
- **Used exclusively** by the main application
- **Purpose**: Place lookups, search results, and API caching
- **Performance**: 95%+ cache hit rates achieved

## 📁 Project Structure

### High-Level Overview

```
TripThread/
├── mobile/                 # Flutter app (iOS, Android, and the Docker web UI)
├── scheduler/              # Trip status script (cron, or the Docker loop)
├── src/                    # Next.js Backend
├── prisma/                 # Database schema
├── documentations/         # Project documentation
├── docker-compose.yml      # Postgres + API + scheduler + Flutter web
├── docker-compose.dev.yml  # Postgres only
├── DOCKER_SETUP.md
└── README.md
```

### Detailed Folder Structure

```
TripThread/
├── mobile/                 # Flutter Mobile App
│   ├── lib/
│   │   ├── config/
│   │   │   └── app_config.dart
│   │   ├── models/         # Data models (User, Trip, Place, etc.)
│   │   ├── services/       # API services
│   │   │   ├── api_service.dart
│   │   │   ├── trip_service.dart
│   │   │   ├── media_service.dart
│   │   │   └── places_service.dart
│   │   ├── providers/      # State management
│   │   │   ├── auth_provider.dart
│   │   │   ├── trip_provider.dart
│   │   │   └── user_provider.dart
│   │   ├── screens/        # UI screens
│   │   │   ├── auth/       # Login, Signup, Password Reset
│   │   │   ├── home/       # Home feed
│   │   │   ├── trip/       # Trip screens
│   │   │   ├── profile/    # User profile
│   │   │   └── discover/   # Discover trips
│   │   ├── widgets/        # Reusable widgets
│   │   └── utils/          # Utilities
│   ├── android/            # Android platform files
│   ├── ios/               # iOS platform files
│   ├── pubspec.yaml
│   ├── Dockerfile          # Flutter web image (nginx on :8080)
│   ├── nginx.conf          # Proxies /api, /chat, and /share to the API
│   └── README.md
│
├── scheduler/              # Trip Status Scheduler (Cron Service)
│   ├── src/
│   │   ├── index.ts            # Main entry point
│   │   ├── tripStatus.ts       # Status update and personal drafts
│   │   ├── memberFinalDraft.ts # Shared unpublished draft (also imported by the API)
│   │   ├── tripEnd.ts          # End-instant helper
│   │   └── startup-logger.ts
│   ├── tests/             # Unit and integration tests
│   ├── dist/              # Compiled JavaScript
│   ├── package.json
│   ├── tsconfig.json
│   ├── Dockerfile
│   ├── start.sh
│   ├── README.md
│   └── SCHEDULER_ARCHITECTURE.md  # Includes the BullMQ history
│
├── src/                    # Next.js Backend
│   ├── app/
│   │   └── api/           # API routes
│   │       ├── auth/      # Authentication
│   │       │   ├── login/
│   │       │   ├── signup/
│   │       │   ├── logout/
│   │       │   ├── refresh-token/
│   │       │   └── forgot-password/
│   │       ├── users/     # User management
│   │       │   ├── [id]/
│   │       │   └── me/
│   │       ├── trips/     # Trip management
│   │       │   ├── [id]/
│   │       │   │   ├── entries/
│   │       │   │   ├── participants/
│   │       │   │   └── end/
│   │       │   └── route.ts
│   │       ├── places/    # Place search and management
│   │       ├── follow/     # Follow/unfollow
│   │       ├── media/      # Media uploads
│   │       ├── admin/      # Admin endpoints
│   │       └── health/     # Health check
│   ├── lib/               # Core utilities
│   │   ├── cache.ts       # Redis caching
│   │   ├── place.ts       # Place management
│   │   ├── auth.ts        # Authentication
│   │   ├── db.ts          # Database utilities
│   │   ├── cloudinary.ts  # Media uploads
│   │   └── services/      # Business logic services
│   ├── config/
│   │   └── env.ts         # Environment variables
│   └── types/             # TypeScript types
│
├── prisma/                 # Database schema
│   ├── schema.prisma      # Prisma schema
│   └── migrations/        # Database migrations
│
├── documentations/         # Project documentation
│   ├── CACHE.md
│   ├── ENVIRONMENT_SETUP.md
│   ├── CLOUDINARY_IMPLEMENTATION.md
│   ├── ISSUE_PRIORITIZATION.md
│   └── README.md
│
├── scripts/               # Utility scripts
│   └── switch_env.sh      # Environment switching
│
├── package.json           # Backend dependencies
├── tsconfig.json          # TypeScript configuration
├── next.config.js         # Next.js configuration
└── README.md
```

## 🚀 Quick Start

### 🐳 Quick Start with Docker (Recommended)

Run the application in Docker: PostgreSQL, the API (REST and chat), the trip scheduler, and the Flutter UI in the browser.

```bash
# 1. Generate local environment files
npm run setup:env

# 2. Spin up the complete stack
npm run docker:up
```

* **App**: [http://localhost:8080](http://localhost:8080) (Flutter web). The page proxies `/api` and `/chat` to the API, so sign-in, trip creation, the thread, chat, and expenses use the same origin.
* **API**: [http://localhost:3000](http://localhost:3000), WebSocket chat at `ws://localhost:3000/chat`. Point a phone or emulator here (`API_BASE_URL=http://10.0.2.2:3000/api` on the Android emulator).
* **Dev Database**: PostgreSQL at `localhost:5432` (`tripthread_dev`; set `POSTGRES_PORT` if 5432 is taken)
* **Test Database**: PostgreSQL at `localhost:5433` (`tripthread_test`)
* **Scheduler**: Starts after the backend is healthy and updates trip statuses every `SCHEDULER_INTERVAL_SECONDS` (default 300)

On boot the backend runs `prisma migrate deploy`, including `20261111120000_personalized_final_posts`, `20261111120000_user_safety_and_conversation_creator`, and `20261113180000_relabel_ready_final_posts_as_draft`. A volume created by the older `db push` entrypoint is baselined once (schema push, then schema migrations marked applied). That data migration stays unmarked so `migrate deploy` rewrites `READY` final posts to `DRAFT`. Set `DB_SCHEMA_MODE=push` or `skip` to opt out. No new Compose service or environment variable is required for personalized final posts, Restrict, Block, or the media screens. Rebuild the `web` image after a Flutter change so port 8080 serves those screens. Put a real `MAPBOX_ACCESS_TOKEN` in `.env` before place search; the stack still boots with a local placeholder.

View Trip Map and the pin dropper use Mapbox on the web UI as well as on iOS and Android. Put a real `MAPBOX_ACCESS_TOKEN` in `.env` and rebuild the `web` image; the token is baked into the Flutter build, and an empty token shows a configuration message instead of a map. Rebuild that image after changing `WEB_API_BASE_URL` (the browser address is baked in too). iOS builds need Swift Package Manager (`flutter config --enable-swift-package-manager`) and iOS 14.

Run the test suites in containers:
```bash
docker compose --profile test run --rm api-tests     # Vitest unit + integration against postgres-test
docker compose --profile test run --rm mobile-tests  # flutter analyze + flutter test
```

`mobile-tests` uses Flutter 3.38.5 (`FLUTTER_IMAGE_TAG`) so `pub get --enforce-lockfile` leaves `mobile/pubspec.lock` unchanged. It copies `mobile/.env.example` to `mobile/.env` when that file is missing.

List or delete orphaned media rows (does not run on deploy):
```bash
docker compose exec backend npm run cleanup:orphan-media
```

To view backend or database logs:
```bash
docker compose logs -f
```

To stop the entire stack:
```bash
npm run docker:down
```

---

### Manual Setup (Without Docker)

### Prerequisites

- Node.js 18+
- Flutter SDK (latest stable)
- PostgreSQL database
- Redis (Upstash) for caching
- Cloudinary account for media storage

### Environment Setup

**Important:** See the complete environment setup guide:
- **[Environment Setup Guide](./documentations/ENVIRONMENT_SETUP.md)**

Quick setup:
```bash
# Backend
cp .env.example .env
# Edit .env with your configuration

# Mobile
cp mobile/.env.example mobile/.env
# Or use the switch script:
./mobile/scripts/switch_env.sh local
```

### Installation

#### Backend

```bash
# Install dependencies
npm install

# Generate Prisma client
npx prisma generate

# Run database migrations
npx prisma migrate dev

# Start development server
npm run dev
```

#### Mobile

```bash
cd mobile

# Install dependencies
flutter pub get

# Run the app
flutter run
```

#### Scheduler

```bash
cd scheduler

# Install dependencies
npm install

# Generate Prisma client
npm run generate

# Run manually (for testing)
npm start
```

## 📚 Documentation

### Core Documentation

- **[Technical handbook](./documentations/technical/README.md)** - Feature-by-feature implementation, data model, optimizations, and the full architecture diagram
- **[Environment Setup](./documentations/ENVIRONMENT_SETUP.md)** - Complete environment configuration guide
- **[Redis, cache, and queues](./documentations/technical/09-redis-cache-and-queues.md)** - Two-tier cache, locks, and rate limits
- **[Media and Cloudinary](./documentations/technical/07-media-cloudinary.md)** - Signed upload, confirm, and quota

### Module Documentation

- **[Mobile App](./mobile/README.md)** - Flutter app setup and structure
- **[Scheduler Service](./scheduler/README.md)** - Trip status scheduler documentation
- **[Scheduler Architecture](./scheduler/SCHEDULER_ARCHITECTURE.md)** - Deep dive into scheduler design

### Additional Documentation

- **[Architecture diagram](./documentations/technical/19-architecture-diagram.md)** - Mermaid frames for the whole system, including a Miro import order
- **[Optimizations](./documentations/technical/18-optimizations.md)** - Indexes, N+1 removal, caching, and pagination

## 🔑 Key Features

### User Management
- User authentication (JWT with refresh tokens)
- User profiles with privacy settings
- Follow/Unfollow system
- Restrict and Block from a direct-message settings screen and from Settings
- User search and discovery

### Trip Management
- Create and manage trips
- Trip statuses: UPCOMING, ONGOING, ENDED
- Automatic status transitions via scheduler
- Trip participants and invitations
- Trip publishing and privacy
- **Final Posts**: Each member gets their own recap, then publishes it themselves
  - Generated automatically when trip ends
  - Editable summary, media selection, and captions
  - Publishing makes final posts visible in home feed

### Trip Threads
- Real-time trip documentation
- Text, media, and location entries
- Place tagging on location entries
- Media uploads (images/videos) via Cloudinary
- **Final Posts**: Each member gets their own recap, then publishes it themselves
  - Intelligent summary generation from trip entries
  - Media curation (one per day, up to 12 items)
  - Editable before publishing
  - Photo picker shows the selection order and stops at 12
  - Published final posts appear in home feed

### Chat
- Direct, group, and trip conversations
- Restrict stops a direct message both ways and keeps the history
- Block also stops follows and profile access, and stops the creator of a trip or group from adding the other person
- Settings lists the people you blocked and the people you restricted
- Shared photos and videos open in one viewer from a chat and from a trip thread

### Places & Location
- Place search and discovery
- Mapbox integration for place data
- Redis caching for place lookups
- Spatial indexing for location queries
- Place sharing and recommendations

### Caching & Performance
- Two-tier caching (Memory + Redis)
- 95%+ cache hit rates
- Batch operations for efficiency
- Cache warming for popular places
- Graceful degradation

## 🛠️ Development

### Backend Development

```bash
# Development server
npm run dev

# Database migrations
npx prisma migrate dev

# Prisma Studio (database GUI)
npx prisma studio

# Type checking
npm run type-check

# Build
npm run build
```

### Mobile Development

```bash
cd mobile

# Run on device/emulator
flutter run

# Build APK
flutter build apk

# Build iOS
flutter build ios
```

### Scheduler Development

```bash
cd scheduler

# Development mode (with watch)
npm run dev

# Run once (the same process Docker and cron invoke)
npm start

# Run tests
npm run test:unit
npm run test:e2e
```

## 🚢 Deployment

### Backend

Production is Railway (Railpack) starting `node server.cjs` so REST and the chat WebSocket share one process. Do not use bare `next start`. The Docker Compose file in this repo is for local runs, not that deploy.

### Mobile

- **Android**: Build APK or use Google Play Store
- **iOS**: Build via Xcode and deploy to App Store

### Scheduler

Deploy the one-shot script on a schedule:
- **Railway Cron** (recommended)
- **GitHub Actions** (scheduled workflows)
- **System Cron** (Linux/Mac servers)

Local Docker is a separate trigger: it loops the same script every five minutes by default. See [DOCKER_SETUP.md](./DOCKER_SETUP.md).

See [Scheduler README](./scheduler/README.md#deployment) for detailed deployment options.

## 🔐 Environment Variables

### Backend Required Variables

```bash
DATABASE_URL=postgresql://...
JWT_SECRET=...
JWT_REFRESH_SECRET=...
REDIS_REST_URL=...
REDIS_REST_TOKEN=...
CLOUDINARY_CLOUD_NAME=...
CLOUDINARY_API_KEY=...
CLOUDINARY_API_SECRET=...
SENDGRID_API_KEY=...
FROM_EMAIL=...
```

### Mobile Required Variables

```bash
API_BASE_URL=http://localhost:3000/api
ENVIRONMENT=development
```

### Scheduler Required Variables

```bash
DATABASE_URL=postgresql://...
LOG_LEVEL=info
```

**Note:** Scheduler does NOT require Redis - it uses zero Redis commands.

For complete environment setup, see [ENVIRONMENT_SETUP.md](./documentations/ENVIRONMENT_SETUP.md).

## 🎯 Architecture Benefits

### Scheduler Design Benefits

- ✅ **Zero Redis usage** - All Redis budget available for API caching
- ✅ **Simple architecture** - No queue management complexity
- ✅ **Reliable** - Database is the source of truth
- ✅ **Easy to debug** - Single execution, clear logs
- ✅ **Cost-effective** - No additional Redis overhead

### Caching Strategy

- **Two-tier caching**: Memory (L1) + Redis (L2)
- **95%+ hit rates** achieved
- **Batch operations** for efficiency
- **Graceful degradation** if Redis unavailable

For detailed cache architecture, see [Redis, cache, and queues](./documentations/technical/09-redis-cache-and-queues.md).

## 📊 Tech Stack Summary

| Component | Technology |
|-----------|-----------|
| **Frontend** | Flutter (Dart): iOS, Android, and the local Docker web UI |
| **Backend** | Next.js 15 (TypeScript), `server.cjs` |
| **Database** | PostgreSQL |
| **ORM** | Prisma |
| **Cache** | Redis (Upstash) |
| **Media Storage** | Cloudinary |
| **Authentication** | JWT |
| **Email** | SendGrid |
| **Location** | Mapbox, Geolocator |
| **Scheduler** | Node.js + TypeScript (one-shot script; cron or the Docker loop) |

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## 📝 License

[Your License Here]

## 🔗 Links

- [Documentation Index](./documentations/README.md)
- [Technical handbook](./documentations/technical/README.md)
- [Environment Setup](./documentations/ENVIRONMENT_SETUP.md)
- [Scheduler Architecture](./scheduler/SCHEDULER_ARCHITECTURE.md)
