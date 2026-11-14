# TripThread - Complete Project Structure

## 📋 Overview
A full-stack social travel application with a Next.js API, a Flutter app, and a trip-status script.
- **Backend**: Next.js 15 (TypeScript) + Prisma ORM + PostgreSQL. `server.cjs` serves REST and the chat WebSocket.
- **App**: Flutter (Dart) with Provider. iOS and Android are the phone builds. Local Docker also serves a Flutter web build.
- **Scheduler**: Node.js (TypeScript) script that runs once and exits. Cron invokes it in production. Local Docker loops it.
- **Media**: Cloudinary integration for image/video uploads
- **Total Files**: ~3,000 source files across backend, mobile, and scheduler

---

## 🗂️ Root-Level Structure

```
/project/
├── src/                          # Next.js backend (API routes, middleware, utilities)
├── mobile/                       # Flutter app (phone builds and the Docker web UI)
├── scheduler/                    # Trip-status script (one run, then exit)
├── prisma/                       # Database schema & migrations
├── scripts/                      # Utility scripts (including the Docker entrypoint)
├── docs/                         # Documentation & templates
├── documentations/               # Environment, cache, and project-structure docs
├── docker-compose.yml            # Local full stack: Postgres, API, scheduler, Flutter web
├── docker-compose.dev.yml        # Local Postgres only (API and Flutter stay on the host)
├── Dockerfile                    # API image (node server.cjs)
├── DOCKER_SETUP.md               # Compose services, migrations, networking
├── QUICKSTART.md                 # Full-stack and hybrid start commands
├── .env, .env.local, .env.example, docker.env.example
├── package.json, tsconfig.json   # Backend dependencies & TypeScript config
├── next.config.js, postcss.config.js, tailwind.config.js  # Next.js configs
└── README.md                     # Project overview
```

---

## 🚀 Backend Structure (`src/`)

### Directory Tree

```
src/
├── app/
│   ├── api/                      # All API routes (Next.js App Router)
│   │   ├── auth/                 # Authentication endpoints
│   │   │   ├── signup/route.ts
│   │   │   ├── login/route.ts
│   │   │   ├── logout/route.ts
│   │   │   ├── refresh-token/route.ts
│   │   │   ├── forgot-password/route.ts
│   │   │   ├── reset-password/route.ts
│   │   │   └── validate-reset-token/route.ts
│   │   ├── users/
│   │   │   ├── route.ts          # GET /users (search)
│   │   │   ├── [id]/route.ts     # GET /users/:id (user profile)
│   │   │   ├── me/route.ts       # GET/PUT/DELETE /users/me (current user, account deletion)
│   │   │   ├── [id]/stats/route.ts  # User statistics
│   │   │   ├── [id]/privacy/route.ts  # Toggle privacy
│   │   │   ├── me/delete/route.ts  # Account deletion handler
│   │   │   ├── me/safety/route.ts  # GET people you blocked or restricted
│   │   │   └── [id]/safety/route.ts  # GET/PUT/DELETE one Restrict or Block row
│   │   ├── trips/
│   │   │   ├── route.ts          # GET/POST /trips
│   │   │   ├── [id]/route.ts     # GET /trips/:id (trip detail)
│   │   │   ├── [id]/end/route.ts # POST /trips/:id/end (end trip; ongoing end writes one DRAFT per member)
│   │   │   ├── [id]/entries/route.ts  # GET /trips/:id/entries (thread entries)
│   │   │   ├── [id]/participants/route.ts  # GET /trips/:id/participants
│   │   │   ├── [id]/invites/route.ts  # GET/POST trip invitations
│   │   │   ├── [id]/places/route.ts   # GET/POST places on trip
│   │   │   ├── [id]/places/[placeOnTripId]/route.ts
│   │   │   ├── [id]/final-post/route.ts  # GET/PUT /trips/:id/final-post (view/edit)
│   │   │   ├── [id]/publish/route.ts # POST /trips/:id/publish (publish final post)
│   │   │   ├── status/route.ts   # GET trip status
│   │   │   └── status.ts         # Trip status logic (scheduler integration)
│   │   ├── feed/
│   │   │   ├── home/route.ts     # GET /feed/home (user feed)
│   │   │   └── discover/
│   │   │       └── trips/route.ts  # GET /feed/discover/trips
│   │   ├── follow/
│   │   │   ├── [userId]/route.ts # GET/POST/DELETE /follow/:userId
│   │   │   ├── requests/route.ts # GET /follow/requests (pending requests)
│   │   │   ├── requests/[requestId]/accept/route.ts
│   │   │   ├── requests/[requestId]/reject/route.ts
│   │   │   └── requests/[requestId]/route.ts
│   │   ├── places/
│   │   │   ├── route.ts          # GET /places (search)
│   │   │   ├── search/route.ts   # GET /places/search
│   │   │   ├── resolve/route.ts  # POST /places/resolve (place details)
│   │   │   └── [id]/route.ts     # GET /places/:id
│   │   ├── media/
│   │   │   ├── route.ts          # GET /media (metadata)
│   │   │   ├── cloudinary-signature/route.ts  # POST get Cloudinary signature
│   │   │   ├── confirm/route.ts  # POST confirm upload & create Media record
│   │   │   ├── delete/route.ts   # POST delete media (remote + DB)
│   │   │   └── quota/route.ts    # GET /media/quota (user storage quota)
│   │   ├── health/route.ts       # GET /health (health check)
│   │   └── discover/
│   │       └── trips/route.ts    # GET /discover/trips
│   └── layout.tsx                # Root layout (if Next.js pages used)
│
├── config/                       # Configuration & constants
│   ├── app_config.ts            # App-wide constants (API URLs, timeouts)
│   ├── cors.ts                  # CORS configuration
│   └── rate_limits.ts           # Rate limiting rules
│
├── data/                        # Mock/seed data
│   ├── mockData.ts              # Mock trips, users, places
│   ├── mockData.md              # Instructions for updating mock data
│   └── seed.ts                  # Database seeding script
│
├── lib/                         # Core utility libraries
│   ├── prisma.ts                # Prisma client singleton
│   ├── db.ts                    # Database utilities
│   ├── cloudinary.ts            # Cloudinary service (upload, delete, signature)
│   ├── auth.ts                  # JWT generation, token validation
│   ├── middleware.ts            # Middleware stacks (withAuth, withRateLimit, withLogging)
│   ├── security.ts              # Security utilities (file validation, CSRF)
│   ├── errors.ts                # Custom error classes (AppError, ValidationError)
│   ├── token_refresh_manager.ts # Token refresh logic
│   ├── validators.ts            # Input validation helpers
│   └── services/                 # Business logic services
│       └── tripFinalizer.ts     # Final post generation, editing, publishing
│
├── middleware.ts                # Next.js middleware (auth checks, token refresh)
│
├── types/                       # TypeScript type definitions
│   ├── api.ts                   # API response types, UserProfile, etc.
│   ├── auth.ts                  # Auth-related types (JWT payload, session)
│   ├── models.ts                # Domain models (Trip, User, Media, etc.)
│   ├── index.ts                 # Central type exports
│   └── errors.ts                # Error response types
│
└── env.ts                       # Environment variable loader & validator
```

### Key API Endpoints Summary

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/auth/signup` | User registration |
| POST | `/auth/login` | User login |
| POST | `/auth/logout` | User logout |
| GET | `/users/me` | Current user profile |
| PUT | `/users/me` | Update profile |
| DELETE | `/users/me` | Soft/full delete account with data erasure |
| GET | `/users/:id` | Public user profile |
| GET | `/users` | Search users |
| POST | `/trips` | Create trip |
| GET | `/trips/:id` | Trip detail |
| POST | `/trips/:id/end` | End trip. An ongoing end writes one unpublished DRAFT per member |
| GET | `/trips/:id/entries` | Thread entries in trip |
| POST | `/trips/:id/entries` | Add entry to trip |
| GET | `/trips/:id/final-post` | The caller's own final-post draft |
| PUT | `/trips/:id/final-post` | The author edits their draft. Unpublished stays DRAFT |
| POST | `/trips/:id/publish` | The author publishes their own final post |
| POST | `/media/cloudinary-signature` | Get signed upload params |
| POST | `/media/confirm` | Confirm upload, create Media record |
| GET | `/follow/:userId` | Follow status |
| POST | `/follow/:userId` | Follow/unfollow |
| GET | `/places/search` | Search places (Google Maps, Mapbox) |
| GET | `/feed/home` | User's home feed |
| GET | `/feed/discover/trips` | Discover public trips |

---

## 📱 Mobile Structure (`mobile/`)

### Flutter App Directory Tree

```
mobile/
├── lib/
│   ├── main.dart                # App entry point
│   ├── config/
│   │   ├── app_config.dart      # App constants (API base URL, timeouts)
│   │   ├── routes.dart          # Go Router setup
│   │   └── theme.dart           # Theme configuration
│   │
│   ├── models/                  # Data models (JSON-serializable)
│   │   ├── user.dart            # User model
│   │   ├── trip.dart            # Trip, TripThreadEntry, Media, Place models
│   │   ├── trip_join_request.dart  # Trip join request model
│   │   ├── follow_status.dart   # Follow/follower status
│   │   ├── pagination.dart      # Pagination wrapper
│   │   ├── api_response.dart    # Generic API response
│   │   └── *.g.dart             # Generated JSON serialization (build_runner)
│   │
│   ├── providers/               # State management (Provider package)
│   │   ├── auth_provider.dart   # Authentication state
│   │   ├── trip_provider.dart   # Trip operations & state
│   │   ├── user_provider.dart   # User search, follow, profile
│   │   ├── feed_provider.dart   # Home feed & discover trips
│   │   ├── final_post_provider.dart  # Final post editing & publishing
│   │   ├── theme_provider.dart  # Dark/light mode
│   │   └── app_provider.dart    # Global app state
│   │
│   ├── screens/                 # UI Screens
│   │   ├── auth/
│   │   │   ├── login_screen.dart
│   │   │   ├── signup_screen.dart
│   │   │   ├── forgot_password_screen.dart
│   │   │   └── reset_password_screen.dart
│   │   ├── home/
│   │   │   ├── home_screen.dart  # Tab navigation (Trips, Discover, Profile)
│   │   │   ├── trips_tab.dart    # User's trips list
│   │   │   └── profile_tab.dart  # User profile (own)
│   │   ├── trip/
│   │   │   ├── trip_detail_screen.dart  # Trip overview
│   │   │   ├── trip_thread_screen.dart  # Trip entries/timeline
│   │   │   ├── trip_participants_screen.dart  # Manage participants
│   │   │   ├── trip_map_screen.dart  # Map view of trip
│   │   │   ├── create_trip_screen.dart  # Create/edit trip
│   │   │   ├── add_entry_screen.dart    # Add thread entry
│   │   │   └── final_post_edit_screen.dart  # Edit and publish final post
│   │   ├── discover/
│   │   │   ├── discover_tab.dart  # Discover trips & users
│   │   │   ├── discover_detail_screen.dart  # Trip/user detail in discovery
│   │   │   └── search_screen.dart  # Global search
│   │   ├── profile/
│   │   │   ├── profile_screen.dart  # User profile (other users)
│   │   │   ├── edit_profile_screen.dart  # Edit profile with avatar upload
│   │   │   └── followers_screen.dart  # Followers/following lists
│   │   └── settings/
│   │       ├── settings_screen.dart  # App settings
│   │       ├── safety_list_screen.dart  # People you blocked or restricted
│   │       ├── help_faq_screen.dart  # In-app help for the product rules
│   │       ├── privacy_screen.dart   # Privacy settings
│   │       ├── notifications_screen.dart
│   │       └── about_screen.dart     # App info, licenses
│   │   └── chat/
│   │       ├── dm_settings_screen.dart  # Restrict, Block, and shared media
│   │       └── group_settings_screen.dart  # Group members and shared media
│   │
│   ├── services/                # API & External Services
│   │   ├── api_service.dart     # HTTP client (Dio) + API calls
│   │   ├── storage_service.dart # Local storage (SharedPreferences)
│   │   ├── cloudinary_service.dart  # Cloudinary upload flow
│   │   ├── auth_service.dart    # Auth token management
│   │   ├── location_service.dart  # Geolocation (geolocator)
│   │   └── notification_service.dart  # Push notifications
│   │
│   ├── widgets/                 # Reusable UI components
│   │   ├── loading_button.dart
│   │   ├── custom_app_bar.dart
│   │   ├── trip_card.dart       # Reusable trip card widget
│   │   ├── user_card.dart       # User profile card
│   │   ├── media_viewer.dart    # Image/video viewer
│   │   ├── media/
│   │   │   ├── media_gallery_viewer.dart  # Shared chat and thread viewer
│   │   │   └── media_seek.dart  # Seek steps, speeds, and grid columns
│   │   └── chat/
│   │       └── conversation_media_strip.dart  # Thumbnail strip and paged grid
│   │   ├── place_picker.dart    # Place selection dialog
│   │   ├── avatar_widget.dart   # Avatar with upload
│   │   └── bottom_sheet_builder.dart
│   │
│   ├── utils/                   # Utility functions
│   │   ├── cloudinary_utils.dart  # Image/video URL transformations
│   │   ├── date_formatter.dart   # Date formatting utilities
│   │   ├── validators.dart      # Input validation (email, username, etc.)
│   │   ├── constants.dart       # App-wide constants
│   │   ├── enums.dart           # Enums (TripStatus, ThreadEntryType)
│   │   └── helpers.dart         # Generic helpers
│   │
│   └── config/ (alt location)
│       └── error_handler.dart   # Global error handling
│
├── pubspec.yaml                 # Flutter dependencies
├── pubspec.lock                 # Locked dependency versions
│
├── android/
│   ├── app/src/main/AndroidManifest.xml  # Android app config
│   ├── app/build.gradle.kts     # Android build config
│   ├── settings.gradle.kts
│   └── local.properties         # Local Android SDK path
│
├── ios/
│   ├── Runner.xcodeproj         # Xcode project
│   ├── Runner/Info.plist        # iOS app config
│   ├── Podfile                  # CocoaPods dependencies
│   └── Runner/Assets.xcassets/  # App icons, images
│
├── web/
│   ├── index.html               # Web entry point
│   ├── manifest.json            # PWA manifest
│   └── icons/                   # Web app icons
│
├── Dockerfile                   # Flutter web image used by docker-compose `web`
├── nginx.conf                   # Serves the build and proxies /api, /chat, /share
├── .dockerignore
│
├── macos/, linux/, windows/     # Desktop platform configs
│
├── test/
│   ├── widget_test.dart
│   ├── unit_tests/
│   └── integration_tests/
│
└── scripts/
    ├── switch_env.sh            # Switch between dev/prod environments
    └── linux_mapbox_pub_get.sh  # Linux pub get workaround for the SPM-only Mapbox iOS plugin
```

Screens that cannot compile for the web (`dart:io` video and files) keep a native file and a web file. `if (dart.library.io)` selects the native one on iOS, Android, and tests. The web file plays video in the browser. The trip map and pin dropper share one Mapbox 3.34 implementation: annotation managers on iOS and Android, GeoJSON style layers on web. Token storage follows the same split: secure storage on the phone, browser local storage in the Docker web UI. `scripts/linux_mapbox_pub_get.sh` lets Linux `flutter pub get` succeed with the Swift Package Manager-only iOS plugin.

### Core Flutter Dependencies

| Package | Purpose |
|---------|---------|
| `provider` | State management |
| `go_router` | Navigation & routing |
| `dio` | HTTP client |
| `json_annotation` | JSON serialization |
| `build_runner` | Code generation (JSON, etc.) |
| `shared_preferences` | Local storage |
| `geolocator` | GPS location |
| `image_picker` | Photo/video selection |
| `cloudinary_flutter` | Cloudinary integration |
| `connectivity_plus` | Network status |
| `mapbox_maps_flutter` | Map display (3.34.2, iOS, Android, and web) |
| `intl` | Internationalization |

---

## ⏱️ Scheduler Structure (`scheduler/`)

### Directory Tree

The scheduler is not a queue. `src/index.ts` connects, calls `updateTripStatuses`, and exits. Open-ended trips (`endDate` null) move to ongoing and stay there until an end is set. There is no BullMQ worker in this tree.

Local Docker (`docker-compose.yml`) starts this container after the API is healthy, then loops `node dist/index.js` every `SCHEDULER_INTERVAL_SECONDS` (default 300). Production cron invokes the same script. See [scheduler/SCHEDULER_ARCHITECTURE.md](../scheduler/SCHEDULER_ARCHITECTURE.md).

```
scheduler/
├── src/
│   ├── index.ts                 # One-shot entry point
│   ├── tripStatus.ts            # UPCOMING → ONGOING → ENDED, plus personal drafts
│   ├── memberFinalDraft.ts      # Unpublished DRAFT shared with the API
│   ├── tripEnd.ts               # Scheduled end instant
│   └── startup-logger.ts        # Startup diagnostics
│
├── tests/
│   ├── tripStatus.unit.test.ts
│   ├── tripStatus.behavior.unit.test.ts
│   ├── tripStatus.integration.test.ts
│   └── memberFinalDraft.unit.test.ts
│
├── dist/                        # Compiled output
├── Dockerfile                   # Image used by the Compose scheduler service
├── package.json
├── tsconfig.json
├── README.md
└── SCHEDULER_ARCHITECTURE.md    # Includes the BullMQ history
```

### Scheduler Responsibilities

The process only moves trip status and, when it ends a due trip, writes a missing unpublished `DRAFT` for each current member. It does not publish that post.

Orphan media cleanup is `npm run cleanup:orphan-media` (`src/scripts/cleanup-orphan-media.ts`). It is not part of this process, and it does not run on deploy. Notification delivery happens in the API when the event occurs. There is no scheduled reminder job in `scheduler/src`.

---

## 📊 Database Structure (`prisma/`)

### Directory Tree

```
prisma/
├── schema.prisma               # Prisma data schema
│                               # Models:
│                               # - User (auth, profile, sensitive fields)
│                               # - Trip (travel itinerary)
│                               # - TripThreadEntry (timeline entries)
│                               # - TripParticipant (trip members)
│                               # - TripJoinRequest (invite system)
│                               # - TripFinalPost (curated trip summaries)
│                               # - Media (Cloudinary-backed files)
│                               # - Place (POI, stay, food locations)
│                               # - PlaceOnTrip (visited places on trip)
│                               # - PlaceShare (shareable place links)
│                               # - Follow / FollowRequest
│                               # - JWTRefreshToken
│                               # - PasswordReset
│                               # - SecurityEvent
│                               # - OAuthAccount (Google/Apple login)
│
└── migrations/                 # Database migrations
    ├── 20250824064635_update_follow_request_schema/
    ├── 20250824065154_fix_follow_request_mapping/
    ├── 20250830185131_trip_join_requests/
    ├── 20251011183851_add_map_and_place_models/
    ├── 20251017185022_add_password_reset_and_security_event/
    ├── 20251028181650_add_spatial_indexes/
    ├── 20251111185636_add_media_service/
    ├── 20251115132149_deprecated_field_removal/
    └── migration_lock.toml
```

### Core Models

| Model | Purpose |
|-------|---------|
| `User` | Users with auth, profile, deletion tracking |
| `Trip` | Travel itinerary with dates, destinations, media |
| `TripThreadEntry` | Timeline entries (text, media, location) |
| `TripParticipant` | Trip member relationships |
| `TripJoinRequest` | Invitation system for trip participation |
| `TripFinalPost` | Curated trip summaries with selected media |
| `Media` | Cloudinary-backed images/videos |
| `Place` | Points of interest (Google/Mapbox sourced) |
| `PlaceOnTrip` | Visited places linked to trips |
| `Follow` / `FollowRequest` | Social following & privacy requests |
| `JWTRefreshToken` | Session token management |
| `PasswordReset` | Secure password reset flow |

---

## 📝 Configuration & Utilities

### Root Config Files

```
project/
├── next.config.js              # Next.js build config
├── tsconfig.json               # TypeScript config (backend)
├── tailwind.config.js          # Tailwind CSS (if UI used)
├── postcss.config.js           # PostCSS plugins
├── package.json                # Backend & root dependencies
├── .env.example                # Example environment variables
├── .env                        # Local env (gitignored)
└── .gitignore                  # Git ignore rules
```

### Documentation

```
docs/
├── pull_request_template.md    # PR template for contributions
```

### Top-level Docs

```
ARCHITECTURE.md                 # System design & tech stack
CLOUDINARY_IMPLEMENTATION.md    # Media service integration guide
ENVIRONMENT_SETUP.md            # Setup instructions (dev, prod)
RACE_CONDITION_ANALYSIS.md      # Concurrency & locking analysis
README.md                       # Project overview & quick start
cursor_rules.md                 # Cursor/Copilot AI rules
```

---

## 🔐 Security & Auth Flow

### Authentication Files

- `src/lib/auth.ts` — JWT token generation, validation
- `src/middleware.ts` — Auth middleware, token refresh
- `src/app/api/auth/*` — Login, signup, password reset endpoints
- `mobile/lib/providers/auth_provider.dart` — Mobile auth state
- `mobile/lib/services/auth_service.dart` — Mobile token management

### Key Security Features

1. **JWT Tokens** with refresh rotation
2. **Rate limiting** on auth endpoints
3. **File validation** (MIME type, size, magic bytes)
4. **Cloudinary signed uploads** (no exposed secrets client-side)
5. **CORS** policy restrictions
6. **Soft deletion** with erasure options (GDPR compliant)

---

## 🚀 Deployment Architecture

### Environment Separation

```
.env.example    → Template (checked in)
.env            → Local dev (gitignored)
.env.local      → Local overrides (gitignored)
.env.production → Production secrets (not in repo)
```

### Deployment Targets

- **Backend**: Vercel, AWS Lambda, or self-hosted Node.js
- **Database**: PostgreSQL (managed service or self-hosted)
- **Scheduler**: Separate Node.js process or cron job service
- **Mobile**: App Store, Google Play
- **Media**: Cloudinary CDN

---

## 📦 Dependencies Summary

### Backend (`package.json` - root)

- **Framework**: `next` 15 (`server.cjs` for REST and chat)
- **ORM**: `@prisma/client`
- **HTTP**: `axios`, `node-fetch`
- **Auth**: `jsonwebtoken`, `bcrypt`
- **Validation**: `zod`
- **Logging**: `winston`
- **Testing**: `vitest`, `supertest`

### Mobile (`pubspec.yaml`)

- **Framework**: `flutter`, `flutter_sdk`
- **State**: `provider`
- **Routing**: `go_router`
- **HTTP**: `dio`
- **Storage**: `shared_preferences`, `flutter_secure_storage` (browser local storage on web)
- **Location**: `geolocator`, `geocoding`
- **Media**: `image_picker`, `video_player`
- **Maps**: `mapbox_maps_flutter` 3.34.2

### Scheduler (`scheduler/package.json`)

- **Runtime**: `node`, `typescript`
- **Database**: `@prisma/client` (shared schema with the API)
- **Trigger**: external cron, or the Docker Compose shell loop. The process itself has no timer.

---

## 🔄 Data Flow Examples

### User Registration

```
User Input (mobile)
  ↓
POST /auth/signup (backend)
  ↓
Validate email, password
  ↓
Create User record (Prisma)
  ↓
Generate JWT + refresh token
  ↓
Store refresh token (DB)
  ↓
Return tokens + user profile (mobile)
  ↓
Store in secure storage + update auth_provider
```

### Trip Creation with Media

```
User selects cover image (mobile)
  ↓
POST /media/cloudinary-signature (get signed params)
  ↓
Direct upload to Cloudinary (client)
  ↓
POST /media/confirm (confirm & create Media record)
  ↓
POST /trips (create trip with coverMediaId)
  ↓
Scheduler watches trip startDate
  ↓
Auto-transition to ONGOING at startDate (scheduler job)
```

### Account Deletion (GDPR Compliance)

```
User clicks DELETE ACCOUNT (mobile)
  ↓
DELETE /users/me (backend)
  ↓
Collect media publicIds
  ↓
Transaction:
  - Delete tokens, sessions, OAuth accounts
  - Delete follow relations
  - Delete trip threads, participants, invites
  - Delete media records
  - Delete user record
  ↓
(Async) DELETE from Cloudinary (if DELETE_REMOTE_MEDIA=true)
  ↓
Return success (mobile shows confirmation)
```

---

## 📱 Key Mobile Screens

| Screen | Purpose | Provider Used |
|--------|---------|---------------|
| LoginScreen | Authentication | AuthProvider |
| SignupScreen | User registration | AuthProvider |
| HomeScreen | Main navigation hub | Multiple |
| TripsTab | User's trips list | TripProvider |
| DiscoverTab | Discover trips & users | FeedProvider, UserProvider |
| TripDetailScreen | Trip overview | TripProvider |
| TripThreadScreen | Trip timeline entries | TripProvider |
| TripParticipantsScreen | Manage trip members | TripProvider |
| FinalPostEditScreen | Edit and publish final post | FinalPostProvider |
| EditProfileScreen | Edit profile + avatar upload | AuthProvider, CloudinaryService |
| ProfileScreen | View user profile | UserProvider |

---

## 🛠️ Build & Deployment Commands

### Backend (Next.js)

```bash
npm run dev              # Dev server
npm run build            # Production build
npm run start            # Production server
npm run lint             # Linting
npm run test             # Run tests
```

### Mobile (Flutter)

```bash
flutter pub get          # Get dependencies
flutter run              # Dev run
flutter build apk        # Android release
flutter build ios        # iOS release
flutter pub run build_runner build  # Generate JSON serialization
```

### Scheduler

```bash
npm run dev              # Dev mode
npm run build            # Build TypeScript
npm run start            # Run one status pass, then exit
npm test                 # Run tests
```

### Database (Prisma)

```bash
npx prisma migrate dev --name <migration_name>  # Create & apply migration
npx prisma migrate deploy                       # Deploy migrations (production)
npx prisma db seed                              # Seed database
npx prisma studio                               # Open DB browser
```

---

## 📋 File Count & Organization

- **Backend (src/)**: ~800+ TypeScript files
- **Mobile (mobile/lib/)**: ~100+ Dart files + generated code
- **Scheduler**: ~50+ TypeScript files
- **Database**: 8 migrations
- **Total**: 3,000+ files (including dependencies)

---

## 🔍 Quick Navigation

| Need | Location |
|------|----------|
| Add API endpoint | `src/app/api/[feature]/route.ts` |
| Add UI screen | `mobile/lib/screens/[feature]/` |
| Add data model | `src/app/types/models.ts` or `mobile/lib/models/` |
| Update DB schema | `prisma/schema.prisma` |
| Change trip status rules | `scheduler/src/tripStatus.ts` |
| Local full stack | `docker-compose.yml`, `DOCKER_SETUP.md` |
| Fix type errors | `src/types/` or `mobile/lib/models/*.dart` |
| Auth logic | `src/lib/auth.ts` + `mobile/lib/providers/auth_provider.dart` |
| API calls | `src/app/api/` + `mobile/lib/services/api_service.dart` |

---

## 📞 Support

For questions on:
- **Architecture**: See `ARCHITECTURE.md`
- **Setup**: See `ENVIRONMENT_SETUP.md`
- **Media**: See `CLOUDINARY_IMPLEMENTATION.md`
- **Concurrency**: See `RACE_CONDITION_ANALYSIS.md`

---

**Generated**: November 16, 2025
**Project**: TripThread (Social Travel App)
