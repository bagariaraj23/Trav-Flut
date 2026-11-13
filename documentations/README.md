# Documentation Index

## Technical handbook

Feature-by-feature implementation notes, the data model, the optimizations, and the full architecture diagram (Mermaid frames you can import into Miro):

- [Technical handbook](./technical/README.md)

The product snapshot the handbook was checked against is [context.json](./context.json). Where they disagree, the handbook follows the code.

## Core Documentation

- [ENVIRONMENT_SETUP.md](./ENVIRONMENT_SETUP.md) - Environment configuration
- [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) - Repository layout
- [RACE_CONDITION_ANALYSIS.md](./RACE_CONDITION_ANALYSIS.md) - Earlier notes on races. The handbook is newer where they differ.

**Note:** Architecture overview is in the [main README](../README.md#-architecture-overview) and, in more detail, in the [technical handbook](./technical/00-system-overview.md).

## Local Docker

The full local stack (Postgres, API, scheduler, and the Flutter UI in the browser) is documented in:

- [DOCKER_SETUP.md](../DOCKER_SETUP.md) - Compose services, migrate-on-boot, networking, and troubleshooting
- [QUICKSTART.md](../QUICKSTART.md) - Full-stack and database-only start commands
- [README.md](../README.md#-quick-start-with-docker-recommended) - Short start path and ports

Production hosting stays Railway / Railpack. This Compose file is for local runs. Personalized final posts, Restrict, Block, and the media screens use the existing migrate-on-boot path. An old `db push` volume leaves the `READY` to `DRAFT` data migration unmarked so that boot runs it. Rebuild the web image after a Flutter change so port 8080 includes them.

## Scheduler Documentation

The scheduler is an independent module located in `/scheduler`. See:
- [scheduler/README.md](../scheduler/README.md) - Quick start, deployment, and usage
- [scheduler/SCHEDULER_ARCHITECTURE.md](../scheduler/SCHEDULER_ARCHITECTURE.md) - Architecture deep dive, including the move off BullMQ
