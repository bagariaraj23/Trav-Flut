# TripThread Mobile App

Flutter mobile application for TripThread.

## Getting Started

### Prerequisites

- Flutter SDK matching `pubspec.yaml` (`>=3.10.0`; the Docker web image uses 3.38.5)
- Dart SDK
- Android Studio / Xcode (for mobile development)
- Backend API running (see main project README), or the full Docker stack

### Environment Setup

**Important:** Environment configuration is centralized. See:
- **[Environment Setup Guide](../documentations/ENVIRONMENT_SETUP.md)** - Complete guide for both backend and mobile environment configuration

Quick setup:
```bash
# Copy example environment file
cp .env.example .env

# Edit .env with your API URL
# Or use the switch script:
./scripts/switch_env.sh local
```

### Installation

```bash
# Install dependencies
flutter pub get

# Run the app against a host or Docker API on port 3000
flutter run
```

### Browser UI (Docker)

`docker compose up --build -d` from the repo root builds this app for the web and serves it at [http://localhost:8080](http://localhost:8080) (or `http://127.0.0.1:8080`). nginx proxies `/api`, `/chat`, and `/share` to the API, so the browser stays on one origin. See [DOCKER_SETUP.md](../DOCKER_SETUP.md).

That image bakes `WEB_API_BASE_URL` (default `http://localhost:8080/api`). Rebuild the `web` service after changing it. Phone and emulator builds keep using `mobile/.env` and call the API on port 3000 (`http://10.0.2.2:3000/api` on the Android emulator).

On the web build:

- View Trip Map and the pin dropper use `mapbox_maps_flutter` 3.34.2. On web, markers and the route are GeoJSON circle, symbol, and line layers, because the annotation managers throw there. iOS and Android still draw those annotations. The web image needs a real `MAPBOX_ACCESS_TOKEN` build arg; rebuild `web` after changing it.
- iOS uses Swift Package Manager only (`flutter config --enable-swift-package-manager`) and requires iOS 14.
- On Linux, `flutter pub get` exits 1 for that iOS plugin because Xcode is missing. `scripts/linux_mapbox_pub_get.sh` (used by the web image and `mobile-tests`) satisfies the check and retries. macOS does not need the script.
- Sign-in stores the session in browser local storage. iOS and Android keep `flutter_secure_storage`.

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter Cookbook](https://docs.flutter.dev/cookbook)

## Project Structure

- `lib/` - Main application code
  - `config/` - Configuration (environment variables)
  - `models/` - Data models (User, Trip, TripFinalPost, etc.)
  - `screens/` - UI screens
    - `trip/` - Trip management screens including `final_post_edit_screen.dart`
  - `services/` - API services
  - `widgets/` - Reusable widgets
  - `providers/` - State management (including `final_post_provider.dart`)
  - `utils/` - Utility functions

## Key Features

- **Trip Management**: Create, edit, and manage trips
- **Final Posts**: Edit and publish curated trip summaries with selected media
- **Social Features**: Follow users, view profiles, discover trips
- **Restrict and Block**: From a direct-message info screen and from Settings. Restrict stops that chat both ways. Block also hides your profile and stops you from adding each other to a trip or group you created.
- **Shared media**: Six thumbnails on a conversation's settings, then a paged grid. The same viewer opens chat and trip-thread photos and videos.
- **Media Upload**: Cloudinary integration for images and videos
- **Location Services**: Place search, location entries, and Mapbox maps on iOS, Android, and the Docker web UI

## Documentation

For complete documentation, see the main project:
- **[Main README](../README.md)** - Project overview, quick start, and architecture
- **[Environment Setup](../documentations/ENVIRONMENT_SETUP.md)** - Environment configuration for backend and mobile
- **[Documentation Index](../documentations/README.md)** - All available documentation
