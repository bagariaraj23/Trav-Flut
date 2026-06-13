# Docker Setup for TripThread

This project supports two different Docker setups tailored for different development needs:

1. **Full-stack Mode** (`docker-compose.yml`): Runs the PostgreSQL databases, Next.js API server, and Scheduler service together in Docker. (Recommended for quick start).
2. **Database-only Mode** (`docker-compose.dev.yml`): Runs only PostgreSQL databases in Docker. The Next.js API and Prisma are run on the host machine. (Recommended for active code modifications).

---

## 1. Full-stack Stack composition

When running the full stack (`npm run docker:up`), the following services are spun up in the `tripthread` bridge network:

| Service | Port (Host) | Port (Internal) | Purpose |
|---------|-------------|-----------------|---------|
| `postgres-dev` | `5432` | `5432` | Development Database (`tripthread_dev`) |
| `postgres-test` | `5433` | `5432` | Integration Test Database (`tripthread_test`) |
| `backend` | `3000` | `3000` | Next.js API server (`http://localhost:3000`) |
| `scheduler` | N/A | N/A | Trip status transitioning background service |

### Internal container networking
Inside the Docker bridge network, services talk to each other using the service names as hostnames:
* Next.js backend and Scheduler connect to the dev DB using:
  `postgresql://postgres:postgres@postgres-dev:5432/tripthread_dev?schema=public`
* Host machine processes (like local Prisma Client or Studio) connect to `localhost:5432`.

### Scheduler behavior
The scheduler container runs the scheduler script once every hour in a shell loop. The console output shows `Waiting 1 hour...` between invocations.

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
If you modify backend code or the database schema, they will be applied automatically to the hybrid setup. For the full Docker setup, rebuild the images:
```bash
npm run docker:up
```

### Resetting database state (wiping data)
If you want to clear your local database tables and start clean:
```bash
npm run docker:reset
```
*Note: This command stops database containers and deletes volumes.*
