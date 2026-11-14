# Documentation Index

## Core Documentation

- [CACHE.md](./CACHE.md) - Redis cache implementation and usage
- [CLOUDINARY_IMPLEMENTATION.md](./CLOUDINARY_IMPLEMENTATION.md) - Cloudinary media storage
- [ENVIRONMENT_SETUP.md](./ENVIRONMENT_SETUP.md) - Environment configuration
- [ISSUE_PRIORITIZATION.md](./ISSUE_PRIORITIZATION.md) - Issue prioritization guidelines

**Note:** Architecture overview is in the [main README](../README.md#-architecture-overview).

## Local Docker

The full local stack (Postgres, API, scheduler, and the Flutter UI in the browser) is documented in:

- [DOCKER_SETUP.md](../DOCKER_SETUP.md) - Compose services, migrate-on-boot, networking, and troubleshooting
- [QUICKSTART.md](../QUICKSTART.md) - Full-stack and database-only start commands
- [README.md](../README.md#-quick-start-with-docker-recommended) - Short start path and ports

Production hosting stays Railway / Railpack. This Compose file is for local runs. Restrict, Block, and the media screens use the existing migrate-on-boot path. Rebuild the web image after a Flutter change so port 8080 includes them.

## Scheduler Documentation

The scheduler is an independent module located in `/scheduler`. See:
- [scheduler/README.md](../scheduler/README.md) - Quick start, deployment, and usage
- [scheduler/SCHEDULER_ARCHITECTURE.md](../scheduler/SCHEDULER_ARCHITECTURE.md) - Complete architecture deep dive
- [scheduler/MIGRATION_NOTES.md](../scheduler/MIGRATION_NOTES.md) - Migration from BullMQ to cron-based execution
