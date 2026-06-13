# Quick Start (Development)

Get the **TripThread API** backend running locally. You have two ways to start the backend services:

---

## Option A: Full Stack in Docker (Fastest & Recommended)

Run the database, Next.js API, and the scheduler services completely containerized. You do not need to install Node.js, PostgreSQL, or Prisma on your host machine.

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
   *This builds and launches the databases, Next.js API server, and scheduler service. It automatically checks database readiness, runs Prisma client generation, and executes database pushes.*

4. **Verify the server:**
   Open [http://localhost:3000/api/health](http://localhost:3000/api/health) in your browser. You should receive a status check showing the API is connected to the database.

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

7. **Run Next.js dev server:**
   ```bash
   npm run dev
   ```
   Open [http://localhost:3000](http://localhost:3000).

8. **Stop databases:**
   ```bash
   npm run docker:stop
   ```

---

## Quick Command Reference

| Command | Stack Mode | Description |
|---------|------------|-------------|
| `npm run docker:up` | Full Stack | Build and start database, Next.js, and scheduler |
| `npm run docker:down` | Full Stack | Stop and remove all containers |
| `npm run docker:start` | Hybrid | Start dev + test PostgreSQL containers |
| `npm run docker:stop` | Hybrid | Stop dev + test PostgreSQL containers |
| `npm run docker:reset` | Hybrid | Wipe dev/test database volumes and restart them |
| `npm run dev` | Hybrid | Next.js dev server on host |
| `npm run db:migrate` | Hybrid | Apply Prisma migrations on dev DB |
| `npm run test` | Hybrid / Tests | Run integration tests (needs test DB on port 5433) |
