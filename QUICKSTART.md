# Quick start (development)

Get the **TripThread API** (Next.js + Prisma) running locally. Databases run in **Docker**; the app runs on the host with **Node 20**.

## Prerequisites

- Node.js **20.x**
- **Docker Desktop** (or Docker Engine + Compose v2)
- Git clone of this repository

## Steps

### 1. Install dependencies

```bash
npm install
```

### 2. Environment

```bash
npm run setup:env
```

Edit **`.env`**: set `JWT_SECRET`, `JWT_REFRESH_SECRET`, and any keys you need (Cloudinary, Mapbox, SendGrid, Google OAuth). The template **`docker.env.example`** (copied by `setup:env`) matches **Docker PostgreSQL on localhost:5432** (dev) and **5433** for the test database.

### 3. Start PostgreSQL (Docker)

```bash
npm run docker:start
```

Starts:

- **Dev** DB → `localhost:5432` → `tripthread_dev`
- **Test** DB → `localhost:5433` → `tripthread_test`

### 4. Database schema

```bash
npm run db:generate
npm run db:migrate
```

### 5. Optional seed

```bash
npm run db:seed
```

### 6. Run the dev server

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

---

## Quick reference

| Command | Purpose |
|---------|---------|
| `npm run dev` | Next.js dev server |
| `npm run docker:start` / `docker:stop` / `docker:reset` | Docker Postgres |
| `npm run db:migrate` | Apply Prisma migrations |
| `npm run db:studio` | Prisma Studio |
| `npm run test` | Tests (needs `.env.test` + test DB on **5433**) |

---

## Docs

- **[DOCKER_SETUP.md](DOCKER_SETUP.md)** — Docker details, connection strings, scheduler image, troubleshooting
- **Mobile app** — `mobile/README.md` (Flutter; separate from Docker Compose here)

---

## Common issues

| Issue | What to do |
|-------|------------|
| Cannot connect to DB | `npm run docker:start`, then check `DATABASE_URL` in `.env` |
| Port 5432 busy | Change `POSTGRES_PORT` in `.env` and update `DATABASE_URL` |
| Tests fail on DB | Ensure `TEST_DATABASE_URL` uses **localhost:5433** and Docker is up |
