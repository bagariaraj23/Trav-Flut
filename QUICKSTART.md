# Quick Start (Development)

Get TripThread running locally. You have two ways to start:

---

## Option A: Full Stack in Docker (Fastest & Recommended)

Run PostgreSQL, the API, the scheduler, and the Flutter UI in the browser. You do not need Node.js, PostgreSQL, Prisma, or Flutter on the host. Production deploys stay on Railway; this stack is local.

### Prerequisites
* **Docker Desktop** (or Docker Engine + Compose v2)

### Steps
1. **Initialize environment configurations:**
   ```bash
   npm run setup:env
   ```
   *Copies `docker.env.example` to `.env` and `.env.test.example` to `.env.test` if they don't already exist.*

2. **(Optional) Edit configurations:**
   Open `.env` and customize secrets (`JWT_SECRET`, `JWT_REFRESH_SECRET`) or integration keys (Cloudinary, Mapbox, SendGrid) if needed. Auth works out of the box with defaults.

3. **Start the complete stack:**
   ```bash
   npm run docker:up
   ```
   *Builds and starts Postgres, the API (`node server.cjs`), the scheduler, and the Flutter web UI. The API waits for Postgres, then runs `prisma migrate deploy`, including the Restrict and Block migration. Rebuild the web image after a Flutter change. The scheduler starts after the API is healthy and loops every `SCHEDULER_INTERVAL_SECONDS` (default 300 seconds).*

4. **Open the app:**
   * Browser UI: [http://localhost:8080](http://localhost:8080) or [http://127.0.0.1:8080](http://127.0.0.1:8080). Sign up, create a trip, and open it. View Trip Map and the pin dropper use Mapbox in the browser once `MAPBOX_ACCESS_TOKEN` is set and the `web` image is rebuilt.
   * API health: [http://localhost:3000/api/health](http://localhost:3000/api/health) and the same path through nginx at [http://localhost:8080/api/health](http://localhost:8080/api/health).
   * Chat: backend logs should show `WebSocket chat endpoint: ws://localhost:3000/chat`. The browser uses the same path on port 8080.
   * Phone or emulator: point `API_BASE_URL` at port 3000 (`http://10.0.2.2:3000/api` on the Android emulator), not at the web container.

5. **Stop the stack:**
   ```bash
   npm run docker:down
   ```

---

## Option B: Hybrid Setup (Databases in Docker, App on Host)

Ideal when you are modifying database schemas, writing integration tests, or debugging Next.js server code interactively on your host machine.

### Prerequisites
* **Docker Desktop**
* **Node.js 20.x**

### Steps
1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Initialize environment configurations:**
   ```bash
   npm run setup:env
   ```

3. **Start databases:**
   ```bash
   npm run docker:start
   ```
   *Starts Postgres Dev DB on host port `5432` and Test DB on host port `5433`.*

4. **Prepare database schema:**
   ```bash
   npm run db:generate
   ```

5. **Apply migrations:**
   ```bash
   npm run db:migrate
   ```

6. **Seed the database (runs on test database):**
   ```bash
   npm run db:seed
   ```

7. **Run the API + chat server on the host:**
   ```bash
   npm run dev
   ```
   This starts `server.cjs` (REST + `ws://localhost:3000/chat`). Do **not** use `npm run next:dev` for the mobile app — that process has no WebSocket upgrade.
   Open [http://localhost:3000/api/health](http://localhost:3000/api/health).

8. **Stop databases:**
   ```bash
   npm run docker:stop
   ```

---

## Quick Command Reference

| Command | Stack Mode | Description |
|---------|------------|-------------|
| `npm run docker:up` | Full Stack | Build and start Postgres, API, scheduler, and Flutter web |
| `npm run docker:down` | Full Stack | Stop and remove the full-stack containers |
| `docker compose down -v` | Full Stack | Also delete the full-stack database volumes |
| `npm run docker:start` | Hybrid | Start dev + test PostgreSQL containers |
| `npm run docker:stop` | Hybrid | Stop dev + test PostgreSQL containers |
| `npm run docker:reset` | Hybrid | Wipe the hybrid Postgres volumes and start them again |
| `npm run dev` | Hybrid | API + chat server on the host (`server.cjs`) |
| `npm run db:migrate` | Hybrid | Apply Prisma migrations on dev DB |
| `npm run test` | Hybrid / Tests | Run integration tests (needs test DB on port 5433) |
