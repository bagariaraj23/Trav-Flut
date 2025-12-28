## TripThread Testing Guide

This document is the central place for all testing: what exists, what is required, and how to run/extend the suite.

---
### Test Types & Locations
- **Unit**: `tests/unit/` — pure logic, no DB/network.
- **Integration**: `tests/integration/` — DB + services/transactions.
- **API**: `tests/api/` — HTTP handlers (Supertest or direct handler invocation).
- **E2E**: `tests/e2e/` — (future) full user flows (Playwright/Cypress).

### Commands (local)
- `npm test` — run all tests (Vitest, watch disabled in CI)
- `npm run test:run` — single-run test command (CI-friendly)
- `npm run test:coverage` — coverage report
- Run only integration tests (example):
  ```bash
  npx vitest run tests/integration --reporter=dot
  ```

### Test execution helpers
- Serial-run script (avoids cross-file parallelism): `scripts/run-integration-serial.mjs`
  - Run it locally:
    ```bash
    node scripts/run-integration-serial.mjs
    ```
- Concurrency helper (library used by stress tests): `tests/integration/concurrencyHelper.ts`
  - Use `runConcurrentCalls(fn, concurrency = 100, rounds = 1)` for stress scenarios.

### Setup Notes
- Requires a **test database**; ensure `DATABASE_URL` points to a local/test Postgres instance. Example:
  ```bash
  export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/test"
  export NODE_ENV=test
  ```
- Before running tests you may need to generate Prisma client and push schema:
  ```bash
  npx prisma generate
  npx prisma db push
  ```
- Utilities: `tests/testUtils.ts` provides `cleanDb`, `createUser`, `createTrip`, `getAuthToken`.
- Isolation: integration suites call `cleanDb()` in `beforeEach` to ensure clean state.

### Verifying `.env.test` is loaded

- To be certain the test suite is using the values from your `.env.test`, the test setup
  helper prints a masked confirmation when running locally. Run the tests and look for a
  line like:

  ```text
  Test env loaded: DATABASE_URL=postgresql://postgres:****@localhost:5432/test, TEST_DATABASE_URL=postgresql://postgres:****@localhost:5432/test
  ```

- If you prefer to quickly check the parsed variables yourself without running the full
  test suite, run:

  ```bash
  node -e "require('dotenv').config({ path: '.env.test' }); console.log('DATABASE_URL=' + (process.env.DATABASE_URL||'(unset)')); console.log('TEST_DATABASE_URL=' + (process.env.TEST_DATABASE_URL||'(unset)'))"
  ```

  Note: `.env` variable expansion (e.g. `TEST_DATABASE_URL=${DATABASE_URL}`) is handled by
  the test setup helper; if you used that pattern in `.env.test`, the helper will expand
  it so both `DATABASE_URL` and `TEST_DATABASE_URL` end up pointing to the same test DB.

### CI / Secrets

- In CI (GitHub Actions) you should NOT commit `.env.test`. Instead configure the job to
 - In CI (GitHub Actions) you should NOT commit `.env.test`. Instead configure the job to
   provide `DATABASE_URL` (or `TEST_DATABASE_URL`) via repository secrets. The included CI
   workflow expects `DATABASE_URL` to be present in the job environment (see
   `.github/workflows/integration-tests.yml`).

- Recommended patterns:
  - Set `DATABASE_URL` as a repository or environment secret in GitHub (e.g. `postgres://...`).
  - If your CI prefers `TEST_DATABASE_URL`, the test setup will use it only when
    `DATABASE_URL` is not set. If both `DATABASE_URL` and `TEST_DATABASE_URL` exist and
    differ the test setup will refuse to proceed to avoid accidentally touching a
    non-test DB. To override that safety check you may set `FORCE_TEST_DB_OVERRIDE=true`
    (not recommended for production-like secrets).

  - Example GitHub Actions snippet (set the secret `DATABASE_URL` in repo settings):

    ```yaml
    jobs:
      integration-tests:
        runs-on: ubuntu-latest
        services:
          postgres:
            image: postgres:15
            env:
              POSTGRES_PASSWORD: postgres
              POSTGRES_USER: postgres
              POSTGRES_DB: test
            ports:
              - 5432:5432
        env:
          NODE_ENV: test
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        steps:
          - uses: actions/checkout@v4
          - uses: pnpm/action-setup@v2 # or use npm/setup-node
          - run: npm ci
          - run: npx prisma generate
          - run: npx prisma db push
          - run: node scripts/run-integration-serial.mjs
    ```

- Avoid pointing `DATABASE_URL` at production databases. The test helper refuses to
  perform destructive cleanup if it detects a mismatch between `TEST_DATABASE_URL` and
  `DATABASE_URL` unless you intentionally provide `TEST_DATABASE_URL`.

---
## Implemented test coverage (current)

These tests are already implemented in the repository and exercised in CI (Vitest):

- **Unit**
  - `tests/unit/cache.unit.test.ts` — tests `bucketCoord` behavior

- **Integration**
  - `tests/integration/userSignup.integration.test.ts` — signup flow and uniqueness checks (email/username), asserts `P2002` handling
  - `tests/integration/followRequests.integration.test.ts` — transactional follow-request behavior and concurrent create handling
  - `tests/integration/tripInvitation.integration.test.ts` — trip invitation flows (owner-checks, self-invite prevention)
  - `tests/integration/concurrency.tripInvite.test.ts` — concurrency test (parallel sendInvitation calls)
  - `tests/integration/stress.concurrent.test.ts` — stress tests for follow & invite (100 concurrent calls × multiple rounds)

---
## Remaining / recommended coverage

Priorities to expand test coverage (short list):

- API-level tests (Supertest or direct handler invocation):
  - `/follow/requests` route end-to-end (HTTP) — success, duplicate/race, self-follow, 404/403
  - `/follow/[userId]` route — private vs public profiles, pending vs follow created
  - Trip accept/reject endpoints (end-to-end) — participant creation and participantCount correctness
  - `/trips/[id]/entries` — ensure entry+tags+media are created atomically and media ownership validation is enforced at commit time
  - `/trips/[id]/end` — ensure final post creation reads up-to-date data inside transaction

- Utility tests:
  - Error mappers: centralize `P2002`→friendly message logic and unit-test mapping
  - `TripInvitationService` edge cases: deleted trip, deleted receiver, concurrent deletes

- Concurrency & race-condition testing:
  - More stress tests (adjust concurrency/rounds) for hot endpoints
  - Add targeted `SELECT FOR UPDATE` scenarios if you introduce row-level locking

---
## Concurrency & Race-Condition Testing Strategy

1. Prefer deterministic DB invariants over brittle timing assertions. For example, assert that after concurrent calls there is at most one DB row for unique keys.
2. Use `Promise.all` (or `runConcurrentCalls`) to create real concurrency in tests.
3. Catch and tolerate expected Prisma `P2002` unique-constraint errors — they indicate the DB enforced uniqueness under race.
4. Where possible, prefer testing transactional behavior by reproducing the same transaction patterns used in the application (e.g., `prisma.$transaction` callbacks) rather than mocking.
5. For stress runs, run several rounds (e.g., 3–5) to increase the chance of races surfacing.

---
## Stress test examples (what we added)

- `tests/integration/stress.concurrent.test.ts` runs two stress scenarios:
  - 100 parallel follow requests × 3 rounds
  - 100 parallel trip invites × 3 rounds

Each stress test asserts the DB invariant (count ≤ 1) and ensures there are no unexpected errors (except `P2002`, which is tolerated).

---
## CI: run integration tests serially

To avoid cross-file interference and reduce flakiness, we added a CI job that runs integration tests file-by-file in series using `scripts/run-integration-serial.mjs`.

Key points for CI configuration (see `.github/workflows/integration-tests.yml`):

- Service: uses `postgres:15` container
- Environment: `DATABASE_URL=postgresql://postgres:postgres@localhost:5432/test` and `NODE_ENV=test`
- Steps:
  1. `npm ci`
  2. `npx prisma generate`
  3. `npx prisma db push`
  4. `node scripts/run-integration-serial.mjs`

This approach reduces test flakiness introduced by Vitest running multiple files in parallel and is compatible with existing test isolation patterns.

---
## How to run tests locally

1. Start a local Postgres (example via Docker):
   ```bash
   docker run --rm -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=test -p 5432:5432 --name tripthread-postgres -d postgres:15
   ```

2. Export env vars (example):
   ```bash
   export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/test"
   export NODE_ENV=test
   ```

3. Generate Prisma client and push schema:
   ```bash
   npx prisma generate
   npx prisma db push
   ```

4. Run all tests (fast):
   ```bash
   npm run test:run
   ```

5. Run integration tests serially (recommended for stability):
   ```bash
   node scripts/run-integration-serial.mjs
   ```

6. Run a single test file:
   ```bash
   npx vitest run tests/integration/concurrency.tripInvite.test.ts --reporter=dot
   ```

7. Run the stress suite (may be slow):
   ```bash
   npx vitest run tests/integration/stress.concurrent.test.ts --reporter=dot
   ```

---
## Adding new tests — checklist

1. Add tests under the correct folder (`tests/unit`, `tests/integration`, or `tests/api`).
2. Use factories from `tests/testUtils.ts`. Extend utils when necessary.
3. Add `await cleanDb()` in `beforeEach` for isolation (integration tests).
4. For concurrency tests, use `runConcurrentCalls` or `Promise.all` and assert DB invariants (counts, unique constraints).
5. Run locally using the serial runner if tests touch the DB across files.

---
## Troubleshooting & tips

- If you see `P2002` (Prisma unique constraint) errors during concurrent tests, that is expected — ensure the test asserts the DB state rather than failing on the raw exception (or adapt the service to map P2002 to a friendly response).
- If tests are flaky across files, run the serial runner: `node scripts/run-integration-serial.mjs`.
- For long-running stress tests, increase timeouts for those specific tests (see Vitest `it(name, options, fn)` syntax).
- Keep `DATABASE_URL` pointed at a disposable test DB to avoid accidental data loss.

---
## Roadmap & next steps

- Add API-level Supertest suites for each route to assert HTTP responses and status codes.
- Add more stress scenarios (larger concurrency, more rounds) and an occasional CI-only stress job (nightly or manual workflow dispatch).
- Add a reconciliation script for external services (Cloudinary) and unit-tests for error mappers and validation helpers.

---
If you'd like, I can open a PR with these docs and the new tests/scripts (or split into multiple PRs: docs, tests, CI). Which approach do you prefer?



npm install eslint@latest --save-dev
