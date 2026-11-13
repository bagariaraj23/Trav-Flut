# TripThread technical handbook

This handbook is the implementation reference for TripThread. It was written from the running code (`prisma/schema.prisma`, `src/`, `mobile/lib/`, `scheduler/`, `server.cjs`) and cross-checked against `documentations/context.json`. Where the product snapshot and the code disagree, the code wins and the difference is called out.

TripThread is a travel social platform. People create trips, post a thread of text, media, and location while the trip is ongoing, split costs on a Money pane, publish a final post when the trip ends, and chat in direct messages, groups, and trip rooms.

## How to read this

Start with the system overview, then the feature that you are changing. The data model and the optimizations chapter are the two pages that cut across every feature. The last page is the full architecture diagram, laid out so it can be pasted into Miro.

| Page | What it covers |
| --- | --- |
| [System overview](./00-system-overview.md) | Processes, trust boundaries, request path, deploy shape |
| [Authentication](./01-authentication.md) | Signup, login, Google, JWT rotation, mobile session storage |
| [Password reset](./02-password-reset.md) | Forgot, reset, token hashing, email, retention |
| [Profiles and privacy](./03-profiles-and-privacy.md) | Self profile, public profile, search, account deletion |
| [Follow system](./04-follow-system.md) | Public follow, private requests, Restrict, and Block |
| [Trip lifecycle](./05-trip-lifecycle.md) | Create, schedule, status, participants, invites, leave |
| [Thread and final posts](./06-thread-and-final-posts.md) | Entries, tags, purge, one final post per member |
| [Media and Cloudinary](./07-media-cloudinary.md) | Signed upload, confirm, quota, orphans |
| [Places, maps, and location](./08-places-maps-location.md) | Mapbox search, pin drop, static maps, device geocoder |
| [Redis, cache, and queues](./09-redis-cache-and-queues.md) | Two-tier cache, locks, rate limits, what is not a queue |
| [Expenses and settlements](./10-expenses-and-settlements.md) | Splits, nets, settle-up. There is no payment gateway |
| [Feed, discover, and posts](./11-feed-discover-posts.md) | Home feed, live rail, discover ranking, post deeplink |
| [Engagements](./12-engagements.md) | Likes, comments, replies, shares |
| [Notifications](./13-notifications.md) | Unified inbox, unread cache, producers |
| [Chat](./14-chat.md) | REST, WebSocket, DM, group, trip rooms |
| [Scheduler and operations](./15-scheduler-and-ops.md) | Status cron, Docker, health, email |
| [Security and middleware](./16-security-middleware.md) | Auth wrapper, rate limits, headers, moderation |
| [Data model](./17-data-model.md) | Every model, enum, and relationship |
| [Optimizations](./18-optimizations.md) | Indexes, N+1 removal, caching, pagination |
| [Architecture diagram](./19-architecture-diagram.md) | Full-system diagram for Miro |

## Stack at a glance

| Layer | Choice |
| --- | --- |
| API | Next.js App Router, TypeScript, REST under `/api` |
| Process | `server.cjs` serves Next.js and the `/chat` WebSocket |
| Database | PostgreSQL via Prisma. UUID primary keys |
| Auth | JWT access (24h) plus rotating refresh (30d), bcrypt cost 12 |
| Cache | In-process LRU plus Upstash Redis (REST). Cache, locks, and rate limits. Not a job queue |
| Media | Cloudinary signed direct upload |
| Maps | Mapbox Geocoding v6 on the server. Mapbox Maps Flutter 3.34.2 on the client. Device geocoder for pin labels |
| App | Flutter, Provider, GoRouter, Dio |
| Scheduler | One-shot Node script. Cron in production. A shell loop in Docker. No Redis |
| Email | SendGrid |

## Related docs that already exist

- [Environment setup](../ENVIRONMENT_SETUP.md)
- [Project structure](../PROJECT_STRUCTURE.md)
- [Race-condition notes](../RACE_CONDITION_ANALYSIS.md)
- [Docker setup](../../DOCKER_SETUP.md)
- [Scheduler architecture](../../scheduler/SCHEDULER_ARCHITECTURE.md)
- [Product snapshot](../context.json)
