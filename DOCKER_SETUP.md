# Docker setup for TripThread (development)

This document is only about **running PostgreSQL in Docker** for local development. The **Next.js API** and **Prisma** still run on your machine with Node.js (`npm run dev`, `npm run db:migrate`). That split matches the current codebase: there is no production-style “all-in-one” Docker stack for the web app in this repo.

For a fast path, see [QUICKSTART.md](QUICKSTART.md).

---

## What Docker provides

| Service | Host port | Purpose |
|--------|-----------|---------|
| PostgreSQL (dev) | `5432` (default) | `DATABASE_URL` — main app data |
| PostgreSQL (test) | `5433` | `TEST_DATABASE_URL` in `.env.test` — Vitest / integration tests |

**Redis:** The API uses **Upstash Redis over HTTPS** (`REDIS_REST_URL`, `REDIS_REST_TOKEN` in `src/env.ts`) when both are set. If they are omitted, the app uses an **in-memory LRU cache**. A local `redis` container is **not** required and is not part of the compose file anymore (it did not match the Upstash client).

**Scheduler:** The `scheduler/` service is a separate Node process (trip status / finalization). It uses the same `DATABASE_URL` / Prisma schema. To run it in Docker, build from the repo root: `docker build -f scheduler/Dockerfile .` (see comments in that file). Typical local dev runs it with `cd scheduler && npm run dev` instead.

---

## Prerequisites

- **Docker Desktop** (or Docker Engine + Compose v2) — `docker compose version` should work.
- **Node.js 20.x** — matches `package.json` / CI expectations.
- Repo cloned; working directory = project root (`tripthread-backend`).

---

## One-time setup on a new laptop

1. **Install JS dependencies**

   ```bash
   npm install
   ```

2. **Environment files**

   ```bash
   npm run setup:env
   ```

   - Creates `.env` from `docker.env.example` (or legacy `.env.docker`) if missing.
   - Creates `.env.test` from `.env.test.example` if missing (test DB on **localhost:5433**).

   Edit `.env`: set at least `JWT_SECRET` and `JWT_REFRESH_SECRET`, plus any Cloudinary / Mapbox / SendGrid / Google keys you need.

3. **Start databases**

   ```bash
   npm run docker:start
   ```

   This runs `docker compose -f docker-compose.dev.yml up -d` (falls back to `docker-compose` if needed).

4. **Prisma**

   ```bash
   npm run db:generate
   npm run db:migrate
   ```

5. **Optional seed**

   ```bash
   npm run db:seed
   ```

6. **Run the API**

   ```bash
   npm run dev
   ```

   App: [http://localhost:3000](http://localhost:3000) (default Next.js port).

---

## npm scripts (Docker)

| Script | Description |
|--------|-------------|
| `npm run docker:start` | Start dev + test PostgreSQL |
| `npm run docker:stop` | Stop containers (keep volumes) |
| `npm run docker:reset` | `down -v`, then `up -d` (wipes data) |
| `npm run docker:ps` | `docker compose … ps` |
| `npm run docker:logs` | Follow logs |

Shell scripts live under `scripts/` and use **`docker compose`** when available.

---

## Connection strings

**Development** (default in `docker.env.example`):

```text
postgresql://postgres:postgres@localhost:5432/tripthread_dev?schema=public
```

**Tests** (must match Docker test container on **5433**):

```text
postgresql://postgres:postgres@localhost:5433/tripthread_test?schema=public
```

If port `5432` is already taken on the host, set `POSTGRES_PORT` in `.env` and the same port in `DATABASE_URL`.

---

## Alternate compose file

`docker-compose.yml` (no `dev` suffix) also defines two PostgreSQL instances on **5432** and **5433** with fixed credentials. Use it if you prefer `docker compose -f docker-compose.yml up -d`. Day-to-day docs assume **`docker-compose.dev.yml`** (project name `tripthread`, env overrides).

---

## Advanced: baseline migrations only

If a database already matches the schema but `_prisma_migrations` is out of sync, **do not** use this on shared prod DB. For a throwaway local DB you may run:

```bash
bash scripts/baseline-migrations.sh
```

It runs `prisma migrate resolve --applied` for **every** folder under `prisma/migrations/`. New machines should use `npm run db:migrate` instead.

---

## Troubleshooting

**Docker not running**

```bash
docker info
```

**Port in use**

- Change `POSTGRES_PORT` / `DATABASE_URL`, or stop the other PostgreSQL.

**Tests cannot connect**

- Ensure `TEST_DATABASE_URL` uses **5433** and `tripthread_test`, and `npm run docker:start` has been run.

**`docker compose` not found**

- Install Docker Compose v2, or use legacy `docker-compose` (the helper scripts try both).

---

## Mobile (Flutter)

The `mobile/` app is **not** started by this Compose file. After the API is up, configure the app’s API base URL (see `mobile` README / `.env` patterns) to point at your machine (e.g. `http://localhost:3000` or your LAN IP for a device).
