# Docker Setup for TripThread

This project supports two different Docker setups tailored for different development needs:

1. **Full-stack Mode** (`docker-compose.yml`): Runs PostgreSQL, the Next.js API, the scheduler, and the Flutter web UI together in Docker. (Recommended for quick start).
2. **Database-only Mode** (`docker-compose.dev.yml`): Runs only PostgreSQL databases in Docker. The Next.js API and Prisma are run on the host machine. (Recommended for active code modifications).

---

## 1. Full-stack Stack composition

When running the full stack (`npm run docker:up`), the following services are spun up in the `tripthread` bridge network:

| Service | Port (Host) | Port (Internal) | Purpose |
|---------|-------------|-----------------|---------|
| `postgres-dev` | `5432` | `5432` | Development Database (`tripthread_dev`) |
| `postgres-test` | `5433` | `5432` | Integration Test Database (`tripthread_test`) |
| `backend` | `3000` | `3000` | `server.cjs`: Next.js REST (`/api`) + WebSocket chat (`/chat`) + share bridge (`/share`) |
| `web` | `8080` | `80` | Flutter web UI. nginx proxies `/api`, `/chat`, `/share`, `/.well-known`, `/_next`, `/forgot-password`, and `/reset-success` to `backend` |
| `scheduler` | N/A | N/A | Trip status transitioning background service |

### Backend runtime (chat + share)
* Full-stack Compose starts **`node server.cjs`** (the image already ran `build-server.mjs`; same as Railway Start). Do not use bare `next start`.
* REST: `http://localhost:3000/api/...`
* Health: `http://localhost:3000/api/health` (Compose healthcheck probes this; it does **not** verify WebSocket).
* Chat WebSocket: `ws://localhost:3000/chat` — confirm in logs: `WebSocket chat endpoint: …/chat`.
* Share bridge + Universal Link files: `http://localhost:3000/share/{token}`, `/.well-known/apple-app-site-association`, `/.well-known/assetlinks.json`.
* Mobile against Docker: set `API_BASE_URL` and `SHARE_LINK_BASE_URL` to the same host (emulator: `http://10.0.2.2:3000`).
* Browser: open `http://localhost:8080` or `http://127.0.0.1:8080`. The web client follows whichever loopback host you opened, so `/api` and `/chat` stay on that origin. The image still bakes `WEB_API_BASE_URL` (default `http://localhost:8080/api`) for the initial target. Rebuild the `web` service after changing `WEB_API_BASE_URL` or `WEB_SHARE_LINK_BASE_URL`. Sign-in stores the session in browser local storage.
* View Trip Map and the pin dropper render a Mapbox map in the browser. Markers and the route on web are GeoJSON style layers, because Mapbox 3.x annotation managers throw on web. iOS and Android keep those annotation managers. Pass a real `MAPBOX_ACCESS_TOKEN` as a build arg (Compose reads it from `.env`) and rebuild `web`; an empty token shows a configuration message instead of tiles.
* Put a real `MAPBOX_ACCESS_TOKEN` in `.env` before place search. The API still boots with a local placeholder when it is unset. Uploads need Cloudinary keys; without them the API runs and uploads fail.

### Schema apply on container start
`scripts/docker-entrypoint.sh` defaults to `DB_SCHEMA_MODE=migrate` (`prisma migrate deploy`). A volume left by the old `db push` entrypoint (tables, no `_prisma_migrations`) is baselined once: `prisma db push`, then `UPDATE "trips" SET "typeSetByUser" = true WHERE "type" IS NOT NULL` only when that column was just added, then `migrate resolve --applied` for every migration. Later boots take `migrate deploy`. `push` (with `ALLOW_DATA_LOSS=1` for `--accept-data-loss`) and `skip` stay as opt-ins. Do not point the `push` path at the Neon production branch.

`npm run docker:reset` wipes the **hybrid** Postgres volumes (`docker-compose.dev.yml`) and starts those databases again. To wipe the full stack, including its database volumes, stop it with `docker compose down -v`.

### Internal container networking
Inside the Docker bridge network, services talk to each other using the service names as hostnames:
* Next.js backend and Scheduler connect to the dev DB using:
  `postgresql://postgres:postgres@postgres-dev:5432/tripthread_dev?schema=public`
* Host machine processes (like local Prisma Client or Studio) connect to `localhost:5432`.

### Scheduler behavior
The scheduler container starts after the backend is healthy, then runs every `SCHEDULER_INTERVAL_SECONDS` (default 300). A failed run retries on the next interval. Trip start and end instants are UTC.

---

## 2. Database-only Mode

If you run `npm run docker:start`, only the databases are run in Docker.

| Service | Host Port | Database Name | Purpose |
|---------|-----------|---------------|---------|
| `postgres-dev` | `5432` | `tripthread_dev` | Dev database for host Next.js app |
| `postgres-test` | `5433` | `tripthread_test` | Test database for host Vitest integration tests |

The databases write their data to persistent Docker volumes:
* `postgres_dev_data` (maps to `/var/lib/postgresql/data` in the dev container)
* `postgres_test_data` (maps to `/var/lib/postgresql/data` in the test container)

---

## 3. Environment Configurations

Run `npm run setup:env` to scaffold your environment files:
* `.env` is created from `docker.env.example`.
* `.env.test` is created from `.env.test.example`.

### Dev Connection Strings
* **From Host**: `postgresql://postgres:postgres@localhost:5432/tripthread_dev?schema=public`
* **From Containers**: `postgresql://postgres:postgres@postgres-dev:5432/tripthread_dev?schema=public`

### Test Connection Strings
* **From Host**: `postgresql://postgres:postgres@localhost:5433/tripthread_test?schema=public`
* **From Containers**: `postgresql://postgres:postgres@postgres-test:5432/tripthread_test?schema=public`

---

## 4. Upstash Redis Caching

Caching uses **Upstash Redis over HTTPS** (`REDIS_REST_URL` and `REDIS_REST_TOKEN` in `.env`). If these are omitted:
* The application gracefully falls back to an **in-memory LRU cache**.
* A local Redis container is **not** required for development.

---

## 5. Troubleshooting

### Databases not ready / connection refused
1. Check if the containers are up:
   ```bash
   npm run docker:ps
   ```
2. If port `5432` is already occupied on your host by a native Postgres installation, you can stop the native Postgres or change the `POSTGRES_PORT` in `.env` (e.g., `POSTGRES_PORT=5434`) and update the `DATABASE_URL` port to match.

### Rebuilding changes
If you modify backend code or the database schema, they will be applied automatically to the hybrid setup (`npm run dev` plus `npm run db:migrate`). For the full Docker setup, rebuild the images:
```bash
npm run docker:up
```
Flutter web changes are picked up only by rebuilding the `web` service (`docker compose up --build -d web`). The browser address is compiled into that image.

### Container tests
```bash
docker compose --profile test run --rm api-tests     # Vitest against postgres-test
docker compose --profile test run --rm mobile-tests  # flutter analyze + flutter test
```
`mobile-tests` uses `FLUTTER_IMAGE_TAG` (default 3.38.5) and copies `mobile/.env.example` to `mobile/.env` when that file is missing.

### Web UI stays on the splash screen
Sign-in used to wait on WebCrypto in the browser. The web build stores tokens in local storage instead, so the splash should clear within a few seconds. Hard-reload if the tab is still running an older image. Open the app as `localhost` or `127.0.0.1`; the client follows that host so the API stays same-origin.

### Resetting database state (wiping data)
If you want to clear your local database tables and start clean:
```bash
npm run docker:reset
```
*Note: This command stops the hybrid database containers and deletes those volumes. It does not remove the full-stack API, web, or scheduler containers. Use `docker compose down -v` for that.*
