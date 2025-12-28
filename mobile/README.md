# TripThread Mobile App

Flutter mobile application for TripThread.

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Dart SDK
- Android Studio / Xcode (for mobile development)
- Backend API running (see main project README)

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

# Run the app
flutter run
```

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter Cookbook](https://docs.flutter.dev/cookbook)

## Project Structure

- `lib/` - Main application code
  - `config/` - Configuration (environment variables)
  - `models/` - Data models
  - `screens/` - UI screens
  - `services/` - API services
  - `widgets/` - Reusable widgets
  - `providers/` - State management
  - `utils/` - Utility functions

## Documentation

For complete documentation, see the main project:
- **[Main README](../README.md)** - Project overview, quick start, and architecture
- **[Environment Setup](../documentations/ENVIRONMENT_SETUP.md)** - Environment configuration for backend and mobile
- **[Documentation Index](../documentations/README.md)** - All available documentation
