## Bolt-Travello Testing Guide

This document is the central place for all testing: what exists, what is required, and how to run/extend the suite.

---
### Test Types & Locations
- **Unit**: `tests/unit/` — pure logic, no DB/network.
- **Integration**: `tests/integration/` — DB + services/transactions.
- **API**: `tests/api/` — HTTP handlers (Supertest or direct handler invocation).
- **E2E**: `tests/e2e/` — (future) full user flows (e.g., Playwright/Cypress).

### Commands
- `npm test` — run all tests (vitest, watch disabled in CI)
- `npm run test:run` — single run (CI-friendly)
- `npm run test:coverage` — coverage report

### Setup Notes
- Requires a **test/dev database**; set `DATABASE_URL` (or a dedicated test env var).
- Utilities: `tests/testUtils.ts` provides `cleanDb`, `createUser`, `createTrip`, `getAuthToken`.
- Isolation: most suites call `cleanDb()` in `beforeEach` to ensure clean state.

---
## Current Coverage (Implemented)
- **Unit**
  - `tests/unit/cache.unit.test.ts` — `bucketCoord` behavior.
- **Integration**
  - `tests/integration/tripInvitation.integration.test.ts` — atomic invitations, no duplicates, owner-only, no self-invite.
  - `tests/integration/followRequests.integration.test.ts` — concurrent follow requests, no duplicates, self-follow rejection.
  - `tests/integration/userSignup.integration.test.ts` — unique email/username enforced (P2002).

---
## Required / Planned Coverage
### Unit (add)
- Helpers: validation, summary builders, utility formatters.
- Error mappers (e.g., Prisma P2002 → friendly errors).

### Integration (add/expand)
- **Follow & Join**
  - `/follow/requests` route end-to-end: success, duplicate/race, self-follow, 404/403.
  - `/follow/[userId]` route: private vs public, pending vs follow created, duplicate prevention.
  - Trip join invite accept/reject flows (tripInvitation + participant count).
- **Trips & Entries**
  - `/trips/[id]/entries`: atomic tagging (entry + tags + media), media ownership validation.
  - `/trips/[id]/end`: final post creation uses freshest data; no stale summaries.
  - Scheduler final-post/status updates: per-trip atomicity.
- **Auth & Profile**
  - Signup/login/refresh-token flows; username/email uniqueness at update time.

### API (add)
- Supertest-based suites for each route above, asserting status codes, JSON shape, and side effects in DB.
- Negative tests: unauthorized, forbidden, missing params, constraint violations.

### E2E (future)
- Happy-path: signup → login → create trip → add entry (media/tagged) → invite/follow → end trip (final post).
- Privacy: private profile follow flow (request pending vs accepted).
- Regression smoke: ensure critical flows don’t regress after deployments.

---
## Adding New Tests
1) Place files under the correct folder (unit/integration/api/e2e).  
2) Use `tests/testUtils.ts` factories; extend them as needed.  
3) Reset DB per test (`cleanDb()` in `beforeEach/afterEach`).  
4) Prefer real transactions over mocks for race/ACID scenarios.  
5) For API routes, use Supertest or direct handler invocation; get auth via `getAuthToken`.

---
## Tips & Best Practices
- Keep data realistic but isolated; avoid hard-coded IDs.
- Assert all expected error codes (400/403/404/409) and rollback behavior.
- Simulate races with `Promise.all` for concurrent calls.
- Keep this README updated as coverage grows; add a checklist of newly added suites.

---
## Roadmap Checklist (High Priority Next)
- API tests: follow requests, follow user, trip entries, trip end.
- Integration: tagging atomicity via route handler; final-post creation via route handler.
- E2E: one happy-path journey plus a private follow flow.

---


npm install eslint@latest --save-dev
