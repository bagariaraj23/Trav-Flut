# TripThread - Travel Social Media Platform

A social media platform for travelers to document and share their trips with friends and followers.

## 🏗️ Architecture Overview

TripThread uses a microservices architecture with the following components:

### 1. Main Application (Next.js)

- **Framework**: Next.js 14 with App Router
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

### 2. Frontend: Flutter Mobile App

- **Platform**: iOS & Android
- **State Management**: Provider
- **Navigation**: GoRouter
- **Storage**: Flutter Secure Storage (for JWT tokens)
- **HTTP Client**: Dio with interceptors
- **Location Services**: Geolocator, Geocoding
- **Media**: Image picker, video player, Cloudinary integration

### 3. Background Job Scheduler (Independent Service)

- **Type**: Independent cron-based service
- **Purpose**: Automatically updates trip statuses (UPCOMING → ONGOING → ENDED)
- **Technology**: Node.js + TypeScript
- **Deployment**: Cron job (Railway, GitHub Actions, or system cron)
- **Zero Redis dependency** - All Redis budget available for API caching

**Key Design Decision:** The scheduler runs as a simple cron-executable script that:
- Executes once per invocation
- Connects directly to PostgreSQL
- Exits after completion
- Uses zero Redis commands

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
├── mobile/                 # Flutter Mobile App
├── scheduler/              # Trip Status Scheduler (Cron Service)
├── src/                    # Next.js Backend
├── prisma/                 # Database schema
├── documentations/         # Project documentation
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
│   └── README.md
│
├── scheduler/              # Trip Status Scheduler (Cron Service)
│   ├── src/
│   │   ├── index.ts        # Main entry point
│   │   ├── tripStatus.ts   # Status update logic
│   │   └── startup-logger.ts
│   ├── tests/             # Unit and integration tests
│   ├── dist/              # Compiled JavaScript
│   ├── package.json
│   ├── tsconfig.json
│   ├── Dockerfile
│   ├── start.sh
│   ├── README.md
│   ├── SCHEDULER_ARCHITECTURE.md
│   └── MIGRATION_NOTES.md  # Migration from BullMQ to cron
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

- **[Environment Setup](./documentations/ENVIRONMENT_SETUP.md)** - Complete environment configuration guide
- **[Cache Implementation](./documentations/CACHE.md)** - Redis caching architecture and usage
- **[Cloudinary Implementation](./documentations/CLOUDINARY_IMPLEMENTATION.md)** - Media storage setup

### Module Documentation

- **[Mobile App](./mobile/README.md)** - Flutter app setup and structure
- **[Scheduler Service](./scheduler/README.md)** - Trip status scheduler documentation
- **[Scheduler Architecture](./scheduler/SCHEDULER_ARCHITECTURE.md)** - Deep dive into scheduler design

### Additional Documentation

- **[Issue Prioritization](./documentations/ISSUE_PRIORITIZATION.md)** - Development priorities

## 🔑 Key Features

### User Management
- User authentication (JWT with refresh tokens)
- User profiles with privacy settings
- Follow/Unfollow system
- User search and discovery

### Trip Management
- Create and manage trips
- Trip statuses: UPCOMING, ONGOING, ENDED
- Automatic status transitions via scheduler
- Trip participants and invitations
- Trip publishing and privacy

### Trip Threads
- Real-time trip documentation
- Text, media, and location entries
- Place check-ins and tagging
- Media uploads (images/videos) via Cloudinary
- Final trip posts with curated media

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

# Run once (simulates cron)
npm start

# Run tests
npm run test:unit
npm run test:e2e
```

## 🚢 Deployment

### Backend

Deploy as a standard Next.js application:
- Vercel (recommended)
- Railway
- Any Node.js hosting platform

### Mobile

- **Android**: Build APK or use Google Play Store
- **iOS**: Build via Xcode and deploy to App Store

### Scheduler

Deploy as a cron job:
- **Railway Cron** (recommended)
- **GitHub Actions** (scheduled workflows)
- **System Cron** (Linux/Mac servers)

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

For detailed cache architecture, see [CACHE.md](./documentations/CACHE.md).

## 📊 Tech Stack Summary

| Component | Technology |
|-----------|-----------|
| **Frontend** | Flutter (Dart) |
| **Backend** | Next.js 14 (TypeScript) |
| **Database** | PostgreSQL |
| **ORM** | Prisma |
| **Cache** | Redis (Upstash) |
| **Media Storage** | Cloudinary |
| **Authentication** | JWT |
| **Email** | SendGrid |
| **Location** | Mapbox, Geolocator |
| **Scheduler** | Node.js + TypeScript (Cron) |

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## 📝 License

[Your License Here]

## 🔗 Links

- [Documentation Index](./documentations/README.md)
- [Environment Setup](./documentations/ENVIRONMENT_SETUP.md)
- [Cache Documentation](./documentations/CACHE.md)
- [Scheduler Architecture](./scheduler/SCHEDULER_ARCHITECTURE.md)
