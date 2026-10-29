# TripThread — scalability and production gaps still open

Updated 2026-10-18. This is the tracked remainder after the API/database branch. Query work that already shipped is listed first so it is not picked up again.

## Shipped on the database branch (do not redo)

- Redis calls fail soft after 250ms, with a circuit breaker.
- `getOrSet` uses a stampede lock.
- Hot-path Prisma indexes (`20261004153000_add_hot_path_query_indexes`, `20261004180000_add_remaining_hot_path_indexes`).
- Home feed keyset cursor (`nextCursor`) and lean trip GET (no embedded thread, preview entries, paged final-post media).
- In-flight request dedupe on the client.
- Rate-limit presets still accept the older `(req, handler)` call shape.

## Still open

### Chat cannot scale past one app instance

`src/lib/chat-events.ts` is an in-process bus. A message saved on instance A never reaches a WebSocket on instance B. Upstash REST Redis cannot do Pub/Sub. Multi-node chat needs a TCP Redis (or another broker) and the Railway service must stay at **one replica** until that exists.

### `GET /users/me` is still uncached

Production logs showed this route around 8 seconds. Trip GET was slimmed down; the profile route still loads the user, OAuth accounts, and a raw password-presence query on every call, with only a rate limit in front. A short private cache (about 10–30 seconds, invalidated on profile PATCH) is the next lever. Do not cache it in a shared key that another user can read.

### Neon connections still drop

Logs show `prisma:error` PostgreSQL connection closed after idle or cold start. Reconnect behavior is partial. The app should retry the first query after a closed connection instead of failing the request.

### Scheduler lag

The local Docker stack runs the trip-status job every `SCHEDULER_INTERVAL_SECONDS` (default 300). The Railway cron is still hourly, so in production a trip can sit in the wrong status for up to an hour if nobody opens it. Read paths call `syncTripById` / `syncViewerTripSchedule`, so an opened trip corrects itself. A tighter schedule, or a scheduled wake at the stored UTC instant, is still missing for trips nobody opens.

### Cloudinary presets are an ops prerequisite

Signed uploads that send `upload_preset` fail unless the Cloudinary dashboard has `tripthread_thread_image`, `cover`, `video`, and `avatar`. This is configuration, not another code change.

### Share links are an ops prerequisite

Set `SHARE_LINK_BASE_URL` to the public Next origin. Replace `TEAMID` and the Android SHA-256 in `public/.well-known/`. Ship a build that uses that origin. See issue 32 in `documentations/remaining-product-issues.md`.

### Races that remain

- Final-post generation on the end-trip route can run twice under concurrent requests.
- Media quota accounting can overshoot under concurrent uploads.

The cache stampede on hot reads is treated as fixed.

## Local Docker stack

`docker compose up --build -d` runs Postgres, the backend (`server.cjs`, REST and `/chat`), and the scheduler. The backend applies migrations with `prisma migrate deploy` and baselines older `db push` volumes once. `docker compose --profile test run --rm api-tests` and `mobile-tests` run the Vitest and Flutter suites in containers. Redis stays Upstash REST; there is no Redis container.

## Explicitly not the next move

Do not add a second Railway replica for chat before Pub/Sub. Do not put platform-specific Rolldown bindings in root `dependencies` (breaks the Linux deploy). Prefer `prisma migrate deploy` over `db push --accept-data-loss` on Neon.
