# Scheduler and operations

The scheduler is a second program with the same database and none of the API's Redis, HTTP, or WebSocket machinery. Operations around it are Docker, health, email, and a few scripts.

## Scheduler

Files: `scheduler/src/index.ts`, `tripStatus.ts`, `tripEnd.ts`, `memberFinalDraft.ts`, `startup-logger.ts`. The BullMQ history is in `scheduler/SCHEDULER_ARCHITECTURE.md`. There is no `scheduler/MIGRATION_NOTES.md`.

`index.ts` loads env, constructs Prisma, logs database health, calls `updateTripStatuses`, and exits. Exit is the feature. Cron, GitHub Actions, or the Compose shell starts the next run. Nothing in this process stays resident, so it cannot leak a Redis connection or a BullMQ worker.

`startup-logger.ts` states there is no Redis dependency. That is checked by reading the scheduler sources: they import Prisma and the duplicated end-instant helper, not `src/lib/redis.ts`.

### What one run does

`updateTripStatuses(prisma, now)` in `tripStatus.ts`:

1. Load trips in `UPCOMING` or `ONGOING` whose stored `endDate` is at or before now, plus `UPCOMING` trips whose `startDate` is at or before now. This is a coarse fetch. Indexes `(status, endDate)` and `(status, startDate)` exist for it.
2. Recompute with `scheduledEndInstant` (copy in `tripEnd.ts`). Midnight ends expand to 23:59:59.999 in `scheduleTimezone`. A trip with `endDate` null is not in the end batch.
3. End batch, one transaction per trip: claim `ENDED` with `updateMany` while the trip is still upcoming or ongoing, then insert missing personal drafts with `createMany` and `skipDuplicates`. A trip the app already ended is skipped. The draft is `DRAFT` and `isPublished` stays false. A member who already has a row is left alone.
4. Start batch: `updateMany` the filtered `UPCOMING` ids to `ONGOING`.
5. Return `{ endedCount, ongoingCount, nowIso }`.

The API does not wait for this. `syncViewerTripSchedule` and `syncTripById` apply the same status rules on read, and when they end a trip they call `TripFinalizerService.generateFinalPostsForMembers`. That service loads the trip once and imports the same `buildMemberFinalDraft`, so a manual end, a read that catches a due end, and this cron write the same unpublished draft. A trip that nobody opens still ends, because cron is the backstop. See [Thread and final posts](./06-thread-and-final-posts.md).

### How it is invoked

| Place | Cadence |
| --- | --- |
| Documented production cron | `0 * * * *` (hourly), from `scheduler/README.md` and the comment in `tripStatus.ts` |
| Docker Compose | After the API healthcheck passes, loop every `SCHEDULER_INTERVAL_SECONDS` (default 300) |
| A developer | `npx tsx src/index.ts` inside `scheduler/`, once |

Docker is a convenience loop around the same one-shot script. It is not a long-running worker with its own queue.

## Docker

`docker-compose.yml` (full local stack) and `docker-compose.dev.yml` (Postgres only). Details: `DOCKER_SETUP.md`, `QUICKSTART.md`.

| Service | Role |
| --- | --- |
| `postgres-dev` | Port 5432 |
| `postgres-test` | Port 5433 |
| `backend` | `node server.cjs` on port 3000. REST and `/chat` |
| `web` | Flutter web, nginx port 8080, proxies API, chat, share, well-known, Next assets, reset pages |
| `scheduler` | The loop described above |

`scripts/docker-entrypoint.sh` waits for Postgres, runs `prisma migrate deploy`, baselines a volume that was previously created with `db push`, then execs the command. Baselining marks schema migrations applied and leaves data-only migrations unmarked, because a schema push does not rewrite stored rows. The `migrate deploy` that follows runs those updates. A database that already has `_prisma_migrations` just runs `migrate deploy`. A feature keeps the current Compose services, ports, and environment variables unless it needs a new one. Rebuild the `web` image after a Flutter change. The scheduler image copies `scheduler/` and compiles it. Production hosting is Railway / Railpack, not this Dockerfile. The image is for local parity.

`SHARE_LINK_BASE_URL` is passed into the backend so share links in emails and API responses point at the host the web container serves.

## Health

`GET /api/health` pings Postgres, returns process metrics, the in-memory `PerformanceMonitor` (last 100 timings, warn over 1 second), and `ErrorTracker` (last 1000 errors). The external-service map on the payload is empty. Health does not call Cloudinary, Mapbox, SendGrid, or Redis, and it does not upgrade to WebSocket. A green healthcheck means the process is up and Postgres answers.

`PerformanceMonitor` timers are placed on the hot feed and discover handlers (`get_home_feed` and the discover equivalent). They are process-local. A restart clears them. There is no Sentry, Datadog, or OpenTelemetry exporter in the repo.

## Email

SendGrid sends three messages: password reset, "your password changed", and a support note. Implementation: `src/lib/services/email.ts`. If `SENDGRID_API_KEY` is unset, password-reset send is a no-op and the API still returns success for forgot-password. That is safe for enumeration and unsafe for a misconfigured production deploy, because the user hears nothing. `MAIL_FROM` defaults to `no-reply@your-domain` and should be a verified sender. `SENDGRID_DEBUG` turns on extra logging.

Support is different. `POST /api/support` (`src/app/api/support/route.ts`, `src/lib/supportMessage.ts`) emails `SUPPORT_EMAIL` (default `bagariaraj23@gmail.com`). The message must be 10 to 4000 characters. A public note must include a valid email. A `Bearer` access token replaces that email with the account and adds the user id. Reply-To is the sender. A filled honeypot field named `website` returns `{ ok: true }` and sends nothing. The `support` rate-limit preset allows 5 requests an hour and logs `RATE_LIMIT_HIT`. If SendGrid is unset or the send throws, the route returns **503** and does not pretend the note was sent. Nothing is written to Postgres. The landing page links to `/support` from the header and the footer. Settings opens the same API from Contact support (`/settings/support`). Neither screen prints the inbox address.

Early access is separate. `GET /api/early-access` returns `{ current, target, ratio }` with `target` fixed at 100. `POST /api/early-access` (`src/app/api/early-access/route.ts`, `src/lib/earlyAccess.ts`) stores one row per email in `early_access_requests`, with an optional name and a platform of `ANDROID` or `IOS`. A second submit for the same email does not add another row and does not send another email. A filled honeypot field named `website` returns success and writes nothing. `POST /api/early-access` allows 5 requests an hour. Reading the count is a separate, looser limit so opening the page does not use up a signup. Android signups call Firebase App Distribution `groups.batchJoin` when `FIREBASE_PROJECT_NUMBER`, `FIREBASE_TESTER_GROUP`, and `FIREBASE_SERVICE_ACCOUNT_JSON` are set, so Firebase emails the tester a download link. SendGrid also sends a note when `SENDGRID_API_KEY` is set. That note includes `FIREBASE_ANDROID_DOWNLOAD_URL` when it is set. iPhone requests are stored and confirmed by email. They do not get a download link. A missing SendGrid key still keeps the row. The landing page counter animates from zero to `current` and draws a ring up to the target.

Chip-in is one more public action. `POST /api/chip-in` (`src/lib/chipIn.ts`) accepts a whole rupee amount from 10 to 10000 and stores it in `chip_ins` as paise. The landing page offers ₹50, ₹100, and ₹200, plus Other. One button opens Razorpay Checkout when `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` are set. `POST /api/chip-in/confirm` checks the payment signature and marks the row `PAID`. Card numbers are not stored. Without those keys the route returns 503 and the row is `FAILED`. The `chip_in` limit is 10 requests an hour.

Follows, comments, and trip invites stay in-app notifications. They are not emailed.

## Scripts

| Script | Purpose |
| --- | --- |
| `src/scripts/cleanupExpiredPasswordResets.ts` | Delete used or expired reset rows older than `RESET_RETENTION_DAYS` (7) |
| `src/scripts/cleanup-orphan-media.ts` | List or `--apply` delete media with no parent, older than `--hours` (24), max 500 |
| `src/scripts/seed.ts` | Dev seed |
| `scripts/build-server.mjs` | Bundle `chat-ws.ts` to `dist/chat-ws.cjs` at image build time |
| `scripts/docker-entrypoint.sh` | Migrate then boot |

Password-reset cleanup and media cleanup are not inside the trip scheduler. Running them on the same cron host is an operator choice. They are separate so a failure in Cloudinary deletes cannot block trip status, and so the scheduler image does not need Cloudinary credentials.

## Monitoring gaps that are real

- No trace across the phone, the API, and Cloudinary. A failed confirm is a client log plus an API log.
- Cache hit rate is the in-process counter behind `/api/admin/cache/metrics`, not a hosted dashboard.
- Chat liveness is not in `/api/health`.
