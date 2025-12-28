# TripThread Testing Documentation

This document provides comprehensive information about the testing strategy, setup, current coverage, and guidelines for the TripThread application.

---

## Table of Contents

1. [Test Architecture & Strategy](#test-architecture--strategy)
2. [Test Setup & Configuration](#test-setup--configuration)
3. [Current Test Coverage](#current-test-coverage)
4. [Test Types & Locations](#test-types--locations)
5. [Running Tests](#running-tests)
6. [Test Utilities & Helpers](#test-utilities--helpers)
7. [Concurrency & Race Condition Testing](#concurrency--race-condition-testing)
8. [Required Tests & Coverage Gaps](#required-tests--coverage-gaps)
9. [CI/CD Integration](#cicd-integration)
10. [Best Practices & Guidelines](#best-practices--guidelines)
11. [Troubleshooting](#troubleshooting)

---

## Test Architecture & Strategy

### Core Principles

1. **Separation of Concerns**: Pure utility functions are separated from infrastructure-dependent code
   - Pure functions (e.g., `cacheUtils.ts`) can be tested without environment setup
   - Infrastructure code (e.g., `cache.ts`) requires proper environment configuration
   - This architecture allows unit tests to run independently without database/external services

2. **Test Isolation**: Each test should be independent and not rely on shared state
   - Integration tests use `cleanDb()` in `beforeEach` to ensure clean state
   - Unit tests have no side effects and are fully isolated

3. **Fail Fast**: Environment validation is strict in production/development
   - No test mode bypasses in production code
   - Tests must provide proper environment setup

4. **Concurrency Testing**: Real-world race conditions are tested with actual concurrent operations
   - Uses `Promise.all` and `runConcurrentCalls` for true concurrency
   - Tolerates expected `P2002` unique constraint errors
   - Asserts database invariants rather than timing-dependent behavior

### Test Pyramid

```
        /\
       /  \  E2E Tests (Future)
      /____\
     /      \  Integration Tests (6 files, 12 tests)
    /________\
   /          \  Unit Tests (2 files, 4 tests)
  /____________\
```

- **Unit Tests**: Fast, isolated, test pure logic
- **Integration Tests**: Test database interactions, transactions, and service integration
- **E2E Tests**: (Future) Full user flows with HTTP endpoints

---

## Test Setup & Configuration

### Environment Variables

Tests use **TEST_* prefixed variables** from `.env.test` ONLY. This ensures complete separation from production variables in `.env`.

**Required TEST_* variables in `.env.test`:**

```bash
# Required
TEST_DATABASE_URL="postgresql://postgres:postgres@localhost:5432/tripthread_test"
TEST_JWT_SECRET="test-jwt-secret-key-for-testing-only"
TEST_MAPBOX_ACCESS_TOKEN="test-mapbox-token"

# Optional (tests can run without Redis)
# TEST_REDIS_REST_URL="https://your-test-redis.upstash.io"
# TEST_REDIS_REST_TOKEN="your-test-redis-token"
```

**How it works:**
- `.env.test` contains TEST_* prefixed variables
- `setupTests.ts` maps TEST_* variables to non-prefixed versions (DATABASE_URL, JWT_SECRET, etc.)
- Application code (Prisma, etc.) uses the non-prefixed versions
- Production code never sees TEST_* variables
- Tests never see production variables from `.env`

**See `.env.test.example` for a template.**

### Configuration Files

#### `vitest.config.ts`
- **Test Framework**: Vitest v4.0.16
- **Environment**: Node.js
- **Globals**: Enabled (no need to import `describe`, `it`, `expect`)
- **Setup File**: `tests/setupTests.ts` (runs before all tests)
- **Test Patterns**: 
  - `tests/**/*.test.ts`
  - `scheduler/tests/**/*.test.ts`
- **Path Aliases**: `@/` → `src/`
- **Execution Mode**: Test files run serially (`fileParallelism: false`, `maxConcurrency: 1`)
  - Prevents flakiness caused by PostgreSQL READ COMMITTED isolation + Prisma connection pooling
  - Tests within a file can still run in parallel (they use `cleanDb()` for isolation)

#### `tests/setupTests.ts`
Automatically executed before all tests. Responsibilities:
1. Forces `NODE_ENV=test` before any imports
2. Loads `.env.test` (contains TEST_* prefixed variables)
3. Validates `TEST_DATABASE_URL` is set (fails fast in CI)
4. Maps TEST_* variables to non-prefixed versions for application code:
   - `TEST_DATABASE_URL` → `DATABASE_URL`
   - `TEST_JWT_SECRET` → `JWT_SECRET`
   - `TEST_MAPBOX_ACCESS_TOKEN` → `MAPBOX_ACCESS_TOKEN`
   - etc.
5. Provides safe test defaults if TEST_* variables are missing
6. Silences noisy logs unless `DEBUG` is set

### Database Setup

Before running tests:

```bash
# 1. Start PostgreSQL (Docker example)
docker run --rm \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=postgres \
  -p 5432:5432 \
  --name tripthread-postgres \
  -d postgres:15

# 2. Create .env.test file (if not exists)
# Copy from example template
cp .env.test.example .env.test

# Or create manually with TEST_* prefixed variables:
cat > .env.test << EOF
TEST_DATABASE_URL="postgresql://postgres:postgres@localhost:5432/tripthread_test"
TEST_JWT_SECRET="test-jwt-secret-key-for-testing-only"
TEST_MAPBOX_ACCESS_TOKEN="test-mapbox-token"
EOF

# 3. Setup test database (creates DB and pushes schema)
./scripts/setup-test-db.sh

# OR manually:
# 3a. Create test database
psql -U postgres -c "CREATE DATABASE tripthread_test;"

# 3b. Generate Prisma client
npx prisma generate

# 3c. Push schema to test database
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/tripthread_test"
npx prisma db push
```

### Safety Guards

The test setup includes safety mechanisms:

1. **Database Protection**: Refuses to run destructive operations on non-test databases
   - Requires `NODE_ENV=test` (enforced by setupTests.ts)
   - Requires `TEST_DATABASE_URL` to be set in `.env.test`
   - Validates `DATABASE_URL` (mapped from `TEST_DATABASE_URL`) matches `TEST_DATABASE_URL`
   - Additional safety: URL must contain "test", "localhost", or "127.0.0.1"

2. **CI Safety**: Fails fast in CI if `DATABASE_URL` is missing
   - Prevents accidental connection to wrong database
   - Provides clear error messages

### Verifying Environment Setup

To verify that `.env.test` is loaded correctly:

1. **Check during test run**: The test setup helper will warn if `DATABASE_URL` is missing
2. **Manual verification**: Run this command to check parsed variables:
   ```bash
   node -e "require('dotenv').config({ path: '.env.test' }); console.log('DATABASE_URL=' + (process.env.DATABASE_URL||'(unset)')); console.log('TEST_DATABASE_URL=' + (process.env.TEST_DATABASE_URL||'(unset)'))"
   ```

**Note**: `.env` variable expansion (e.g., `TEST_DATABASE_URL=${DATABASE_URL}`) is handled by the test setup helper. If you use this pattern in `.env.test`, the helper will expand it so both `DATABASE_URL` and `TEST_DATABASE_URL` point to the same test database.

---

## Current Test Coverage

### Test Statistics

**Last Run**: All tests passing ✅
- **Test Files**: 8 passed
- **Total Tests**: 16 passed
- **Duration**: ~4.89s

### Coverage Report

```
-------------------|---------|----------|---------|---------|
File               | % Stmts | % Branch | % Funcs | % Lines |
-------------------|---------|----------|---------|---------|
All files          |   33.58 |    31.76 |      50 |   33.2  |
-------------------|---------|----------|---------|---------|
scheduler/src      |      15 |     5.26 |      20 |   13.79 |
  tripStatus.ts    |      15 |     5.26 |      20 |   13.79 |
-------------------|---------|----------|---------|---------|
src/lib            |   30.06 |    27.36 |   57.89 |   30.37 |
  auth.ts          |    7.31 |       15 |    90.9 |    7.31 |
  cacheUtils.ts    |   39.28 |     8.33 |      25 |   45.83 |
  errors.ts        |   31.57 |    18.18 |      30 |   31.57 |
  prisma.ts        |   85.71 |    66.66 |      50 |   83.33 |
  tripInvitation.ts|   33.82 |    34.78 |   85.71 |   33.82 |
-------------------|---------|----------|---------|---------|
tests              |   66.66 |    68.57 |   66.66 |   68.96 |
  testUtils.ts     |   66.66 |    68.57 |   66.66 |   68.96 |
-------------------|---------|----------|---------|---------|
tests/integration  |   91.66 |      100 |   66.66 |     100 |
  concurrencyHelper|   91.66 |      100 |   66.66 |     100 |
-------------------|---------|----------|---------|---------|
```

### Coverage Analysis

**Well Covered**:
- `prisma.ts`: 85.71% statements, 83.33% lines
- Integration test helpers: 91.66% coverage
- Test utilities: 66.66% coverage

**Needs Improvement**:
- `auth.ts`: Only 7.31% coverage (authentication logic)
- `tripStatus.ts`: 15% coverage (scheduler logic)
- `cacheUtils.ts`: 39.28% coverage (utility functions)
- `tripInvitation.ts`: 33.82% coverage (invitation service)

---

## Test Types & Locations

### Unit Tests (`tests/unit/`)

**Purpose**: Test pure logic without database or external dependencies.

**Current Tests**:
1. **`cache.unit.test.ts`** (2 tests)
   - Tests `bucketCoord` function from `cacheUtils.ts`
   - Validates coordinate encoding and rounding behavior
   - No environment setup required (pure function)

**Architecture Note**: The `cacheUtils.ts` module was extracted to allow unit testing without environment dependencies. This follows the separation of concerns principle.

### Integration Tests (`tests/integration/`)

**Purpose**: Test database interactions, transactions, and service integration.

**Current Tests**:

1. **`userSignup.integration.test.ts`** (2 tests)
   - User signup flow and uniqueness checks
   - Email and username uniqueness validation
   - Tests `P2002` Prisma error handling

2. **`followRequests.integration.test.ts`** (2 tests)
   - Transactional follow-request behavior
   - Concurrent create handling
   - Ensures only one follow request is created under race conditions

3. **`tripInvitation.integration.test.ts`** (2 tests)
   - Trip invitation flows
   - Owner permission checks
   - Self-invite prevention

4. **`concurrency.tripInvite.test.ts`** (2 tests)
   - Concurrency test for parallel `sendInvitation` calls
   - Validates database invariants under concurrent load

5. **`stress.concurrent.test.ts`** (2 tests)
   - **Stress: 100x parallel follow requests** (3 rounds)
   - **Stress: 100x parallel trip invites** (3 rounds)
   - Validates system behavior under high concurrency

### Scheduler Tests (`scheduler/tests/`)

**Purpose**: Test the trip status scheduler service.

**Current Tests**:
1. **`tripStatus.unit.test.ts`** (3 tests)
   - Unit tests for scheduler logic

2. **`tripStatus.integration.test.ts`** (1 test)
   - Integration test for scheduler with database

---

## Running Tests

### Commands

```bash
# Run all tests (watch mode disabled in CI)
npm test

# Single run (CI-friendly)
npm run test:run

# Coverage report
npm run test:coverage

# Run specific test file
npx vitest run tests/unit/cache.unit.test.ts

# Run integration tests only
npx vitest run tests/integration --reporter=dot

# Run stress tests (may be slow)
npx vitest run tests/integration/stress.concurrent.test.ts --reporter=dot

# Run tests serially (recommended for stability)
node scripts/run-integration-serial.mjs
```

### Local Development Workflow

```bash
# 1. Start test database
docker run --rm \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=test \
  -p 5432:5432 \
  --name tripthread-postgres \
  -d postgres:15

# 2. Set environment variables
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/test"
export NODE_ENV=test

# 3. Setup database schema
npx prisma generate
npx prisma db push

# 4. Run tests
npm run test:run

# 5. Check coverage
npm run test:coverage
```

### Serial Test Execution

For stability, especially when tests touch the database across files:

```bash
node scripts/run-integration-serial.mjs
```

This script runs integration tests file-by-file in series, reducing cross-file interference and flakiness.

---

## Test Utilities & Helpers

### `tests/testUtils.ts`

Provides reusable test utilities:

- **`cleanDb()`**: Wipes database tables in dependency-safe order
  - Safety checks: refuses to run on non-test databases
  - Used in `beforeEach` for test isolation

- **`createUser(params)`**: Factory function to create test users
  - Returns user with hashed password
  - Supports custom email, username, password

- **`createTrip(params)`**: Factory function to create test trips
  - Returns trip with owner relationship
  - Supports custom status, type, mood

- **`getAuthToken(userId)`**: Generates JWT token for authenticated requests
  - Uses `AuthService` to create valid tokens
  - Useful for API endpoint testing

### `tests/integration/concurrencyHelper.ts`

Provides concurrency testing utilities:

- **`runConcurrentCalls(fn, concurrency, rounds)`**
  - Executes function `concurrency` times in parallel
  - Repeats for `rounds` rounds
  - Returns results and handles errors gracefully
  - Used by stress tests for realistic concurrency simulation

### Example Usage

```typescript
import { cleanDb, createUser, createTrip, getAuthToken } from '../testUtils';
import { runConcurrentCalls } from './concurrencyHelper';

describe('My Test Suite', () => {
  beforeEach(async () => {
    await cleanDb(); // Ensure clean state
  });

  it('should handle concurrent operations', async () => {
    const user = await createUser({ email: 'test@example.com' });
    
    const results = await runConcurrentCalls(
      async () => {
        // Your concurrent operation
        return await someService.doSomething();
      },
      100, // concurrency
      3    // rounds
    );
    
    // Assert invariants
    expect(results.successful).toBeGreaterThan(0);
  });
});
```

---

## Concurrency & Race Condition Testing

### Strategy

1. **Real Concurrency**: Use `Promise.all` or `runConcurrentCalls` for actual parallel execution
2. **Database Invariants**: Assert final state, not intermediate timing
3. **Tolerate Expected Errors**: `P2002` unique constraint errors are expected and indicate proper DB enforcement
4. **Multiple Rounds**: Run stress tests in multiple rounds to increase chance of races surfacing

### Current Stress Tests

**`tests/integration/stress.concurrent.test.ts`**:

1. **100x Parallel Follow Requests** (3 rounds)
   - Tests concurrent follow request creation
   - Validates only one request is created per (followerId, followeeId) pair
   - Tolerates `P2002` errors (expected under race conditions)

2. **100x Parallel Trip Invites** (3 rounds)
   - Tests concurrent trip invitation creation
   - Validates only one invitation is created per (tripId, receiverId) pair
   - Ensures transactional integrity

### Best Practices

- ✅ Assert database invariants (count ≤ 1 for unique constraints)
- ✅ Use transactions in production code to handle races
- ✅ Test with realistic concurrency levels (100+ parallel operations)
- ❌ Don't assert timing-dependent behavior
- ❌ Don't fail tests on expected `P2002` errors

---

## Required Tests & Coverage Gaps

### High Priority

#### API-Level Tests (Missing)

1. **`/api/follow/[userId]` Route**
   - [ ] GET: Check follow status (public vs private profiles)
   - [ ] POST: Create follow request (private) vs direct follow (public)
   - [ ] POST: Handle pending request scenarios
   - [ ] POST: Prevent self-follow
   - [ ] DELETE: Unfollow user
   - [ ] Error cases: 404, 401, 403

2. **`/api/follow/requests` Route**
   - [ ] GET: List pending follow requests
   - [ ] POST: Accept/reject follow request
   - [ ] Concurrent request handling

3. **`/api/trips/[id]/entries` Route**
   - [ ] POST: Create entry with tags and media
   - [ ] Atomic creation (entry + tags + media)
   - [ ] Media ownership validation
   - [ ] Transaction rollback on failure

4. **`/api/trips/[id]/end` Route**
   - [ ] Final post creation
   - [ ] Reads up-to-date data inside transaction
   - [ ] Trip status transition
   - [ ] Participant count accuracy

5. **`/api/trips/[id]/invites` Route**
   - [ ] Accept/reject trip invitations
   - [ ] Participant creation
   - [ ] Participant count updates

#### Unit Tests (Missing)

1. **Error Mappers** (`src/lib/errors.ts`)
   - [ ] `P2002` → friendly message mapping
   - [ ] Authentication error handling
   - [ ] Rate limit error handling
   - [ ] Centralized error transformation logic

2. **Auth Service** (`src/lib/auth.ts`)
   - [ ] Token generation
   - [ ] Token verification
   - [ ] Token expiration handling
   - [ ] Password hashing/verification

3. **Cache Utils** (`src/lib/cacheUtils.ts`)
   - [ ] `cacheKeys` object methods
   - [ ] Edge cases for coordinate encoding
   - [ ] Key generation for all query types

4. **Trip Invitation Service** (`src/lib/tripInvitation.ts`)
   - [ ] Edge cases: deleted trip
   - [ ] Edge cases: deleted receiver
   - [ ] Concurrent delete handling
   - [ ] Permission validation

#### Integration Tests (Missing)

1. **Trip Lifecycle**
   - [ ] Trip creation → active → ended flow
   - [ ] Status transitions
   - [ ] Final post creation

2. **Media Management**
   - [ ] Cloudinary upload integration
   - [ ] Media quota enforcement
   - [ ] Media deletion

3. **Place Search & Caching**
   - [ ] Place search with caching
   - [ ] Cache invalidation
   - [ ] Spatial indexing

### Medium Priority

1. **Scheduler Service** (`scheduler/src/tripStatus.ts`)
   - [ ] Trip status updates
   - [ ] Scheduled job execution
   - [ ] Error handling and retries

2. **Rate Limiting**
   - [ ] Rate limit enforcement
   - [ ] Different limits for different endpoints
   - [ ] Rate limit reset behavior

3. **Password Reset Flow**
   - [ ] Token generation
   - [ ] Token validation
   - [ ] Password update
   - [ ] Token expiration

### Low Priority

1. **E2E Tests** (Future)
   - Full user flows with Playwright/Cypress
   - Multi-step workflows
   - UI interactions

---

## CI/CD Integration

### GitHub Actions Workflow

The project includes CI configuration for automated testing:

```yaml
# .github/workflows/integration-tests.yml (example)
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
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npx prisma generate
      - run: npx prisma db push
      - run: node scripts/run-integration-serial.mjs
```

### CI Best Practices

1. **Secrets Management**: 
   - Use GitHub repository secrets for `DATABASE_URL`
   - **Do NOT commit `.env.test`** to the repository
   - Configure the CI job to provide `DATABASE_URL` via repository secrets
   - The CI workflow expects `DATABASE_URL` to be present in the job environment

2. **Serial Execution**: Run integration tests serially to avoid flakiness
3. **Database Service**: Use GitHub Actions services for PostgreSQL
4. **Fail Fast**: CI fails immediately if `DATABASE_URL` is missing
5. **Database Safety**: The test helper refuses to perform destructive cleanup if it detects a mismatch between `TEST_DATABASE_URL` and `DATABASE_URL` unless you intentionally provide `TEST_DATABASE_URL`

### Local CI Simulation

To simulate CI environment locally:

```bash
export CI=true
export GITHUB_ACTIONS=true
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/test"
npm run test:run
```

---

## Best Practices & Guidelines

### Writing Tests

1. **Test Naming**: Use descriptive names that explain what is being tested
   ```typescript
   // ✅ Good
   it('creates a single follow request even under concurrent calls', ...)
   
   // ❌ Bad
   it('test follow', ...)
   ```

2. **Test Isolation**: Always use `cleanDb()` in `beforeEach` for integration tests
   ```typescript
   beforeEach(async () => {
     await cleanDb();
   });
   ```

3. **Use Factories**: Use `createUser`, `createTrip` instead of raw Prisma calls
   ```typescript
   // ✅ Good
   const user = await createUser({ email: 'test@example.com' });
   
   // ❌ Bad
   const user = await prisma.user.create({ ... });
   ```

4. **Assert Invariants**: For concurrency tests, assert final state, not timing
   ```typescript
   // ✅ Good
   const count = await prisma.followRequest.count({ ... });
   expect(count).toBeLessThanOrEqual(1);
   
   // ❌ Bad
   expect(result).not.toThrow(); // Timing-dependent
   ```

5. **Handle Expected Errors**: Tolerate `P2002` errors in concurrency tests
   ```typescript
   const results = await runConcurrentCalls(async () => {
     try {
       return await service.create();
     } catch (error) {
       if (error.code === 'P2002') return { error: 'duplicate' };
       throw error;
     }
   });
   ```

### Test Organization

1. **File Structure**: Follow the existing pattern
   - Unit tests: `tests/unit/[module].unit.test.ts`
   - Integration tests: `tests/integration/[feature].integration.test.ts`

2. **Test Groups**: Use `describe` blocks to group related tests
   ```typescript
   describe('User Signup', () => {
     describe('Email Uniqueness', () => {
       it('prevents duplicate emails', ...);
     });
   });
   ```

3. **Setup/Teardown**: Use `beforeEach` and `afterEach` appropriately
   - `beforeEach`: Setup (e.g., `cleanDb()`)
   - `afterEach`: Cleanup (if needed)

### Performance

1. **Test Speed**: Keep unit tests fast (< 1ms each)
2. **Integration Tests**: Acceptable to be slower (100-1000ms)
3. **Stress Tests**: Can be slow (500ms+), run separately if needed

---

## Troubleshooting

### Common Issues

#### 1. `TEST_DATABASE_URL is not set`

**Symptom**: Warning or error about missing `TEST_DATABASE_URL`

**Solution**:
```bash
# Create .env.test file with TEST_* prefixed variables
cat > .env.test << EOF
TEST_DATABASE_URL="postgresql://postgres:postgres@localhost:5432/tripthread_test"
TEST_JWT_SECRET="test-jwt-secret-key-for-testing-only"
TEST_MAPBOX_ACCESS_TOKEN="test-mapbox-token"
EOF

# Or copy from example
cp .env.test.example .env.test
```

#### 2. `P2002` Unique Constraint Errors

**Symptom**: Prisma errors about unique constraints in concurrent tests

**Solution**: This is expected! The database is enforcing uniqueness correctly. Your test should:
- Tolerate these errors
- Assert the final database state (count ≤ 1)

#### 3. Flaky Tests Across Files

**Symptom**: Tests pass individually but fail when run together

**Root Cause**: This is caused by PostgreSQL's READ COMMITTED isolation level combined with Prisma's connection pooling. When tests run in parallel:
- Multiple tests use different connections from the pool
- A connection that commits data might not be immediately visible to other connections
- Timing-dependent visibility issues occur

**Solution**: Tests are now configured to run serially by default in `vitest.config.ts`:
```typescript
fileParallelism: false, // Disable parallel file execution
maxConcurrency: 1,       // Only one test file at a time
```

This eliminates flakiness while still allowing tests within a file to run in parallel (they use `cleanDb()` for isolation).

**Note**: The flakiness is NOT a bug in your application logic - it's a test infrastructure issue. Your business logic is correct, and the tests validate that correctly.

#### 4. Tests Hanging

**Symptom**: Tests never complete

**Solution**:
- Check database connection
- Verify `DATABASE_URL` is correct
- Ensure database is running
- Check for unclosed connections

#### 5. Import Errors

**Symptom**: `Cannot find module '@/...'` or similar

**Solution**: Verify `vitest.config.ts` has correct path aliases:
```typescript
resolve: {
  alias: {
    "@": path.resolve(__dirname, "src"),
  },
}
```

### Debug Mode

Enable verbose logging:

```bash
DEBUG=* npm test
```

### Database Connection Issues

1. **Verify PostgreSQL is running**:
   ```bash
   docker ps | grep postgres
   ```

2. **Test connection**:
   ```bash
   psql $DATABASE_URL -c "SELECT 1;"
   ```

3. **Check Prisma connection**:
   ```bash
   npx prisma db push
   ```

---

## Architecture Notes

### Environment Variable Separation

**Core Principle**: Tests use TEST_* prefixed variables from `.env.test` ONLY. Production code uses non-prefixed variables from `.env`. This ensures complete isolation.

**Variable Mapping**:

| Test Variable (`.env.test`) | Application Variable (mapped by `setupTests.ts`) |
|----------------------------|---------------------------------------------------|
| `TEST_DATABASE_URL` | `DATABASE_URL` |
| `TEST_JWT_SECRET` | `JWT_SECRET` |
| `TEST_MAPBOX_ACCESS_TOKEN` | `MAPBOX_ACCESS_TOKEN` |
| `TEST_REDIS_REST_URL` | `REDIS_REST_URL` (optional) |
| `TEST_REDIS_REST_TOKEN` | `REDIS_REST_TOKEN` (optional) |

**How It Works**:
1. `vitest.config.ts` sets `NODE_ENV=test` before any imports
2. `setupTests.ts` runs (before any application code):
   - Loads `.env.test` (contains TEST_* prefixed variables)
   - Maps TEST_* variables to non-prefixed versions for application code
3. Application code imports:
   - `src/env.ts` validates `DATABASE_URL`, `JWT_SECRET` (already set from TEST_*)
   - `src/lib/prisma.ts` uses `DATABASE_URL` (from TEST_DATABASE_URL)
4. Tests run with test database and test secrets

**Benefits**:
- ✅ Complete isolation: Tests never see production variables
- ✅ Clear separation: `.env` = Production, `.env.test` = Tests
- ✅ Type safety: Application code uses standard variable names
- ✅ Safety guards: Tests refuse to run if `NODE_ENV !== "test"` or `TEST_DATABASE_URL` is missing

### Separation of Concerns

The codebase follows a clean architecture pattern:

1. **Pure Utilities** (`src/lib/cacheUtils.ts`)
   - No dependencies on environment or external services
   - Can be tested in isolation
   - Example: `bucketCoord`, `cacheKeys`

2. **Infrastructure Code** (`src/lib/cache.ts`)
   - Depends on environment variables
   - Requires Redis/external services
   - Re-exports pure utilities for backward compatibility

3. **Benefits**:
   - Unit tests don't require environment setup
   - Faster test execution
   - Better testability
   - Clearer code organization

### Environment Validation

- **Strict in Production**: `src/env.ts` validates all required environment variables
- **Test Mode Handling**: In test mode, `src/env.ts` expects variables to already be set by `setupTests.ts` and provides defaults instead of exiting
- **Test Setup**: `setupTests.ts` runs before any imports to ensure `.env.test` is loaded and TEST_* variables are mapped
- **No Production Bypasses**: Production code remains strict; test handling is in setup only

### Mocking Strategy

**For Unit Tests**: Test pure business logic without external dependencies.

```typescript
// Example: Testing cacheUtils (pure functions)
import { bucketCoord } from '../../src/lib/cacheUtils';

// No mocks needed - pure function, no dependencies
describe('bucketCoord', () => {
  it('encodes coordinates correctly', () => {
    expect(bucketCoord(12.34567)).toBe('...');
  });
});
```

**For Integration Tests**: Test database interactions with real database, but mock external services.

```typescript
import { vi } from 'vitest';

// Mock Redis/Upstash
vi.mock('../../src/lib/cache', () => ({
  cacheGetJson: vi.fn(),
  cacheSetJson: vi.fn(),
}));

// Mock Cloudinary
vi.mock('../../src/lib/cloudinary', () => ({
  uploadToCloudinary: vi.fn(),
}));
```

---

## Roadmap

### Short Term

- [ ] Add API-level tests for all routes
- [ ] Increase coverage for `auth.ts` (target: 70%+)
- [ ] Add unit tests for error mappers
- [ ] Complete `cacheUtils.ts` test coverage

### Medium Term

- [ ] Add E2E tests with Playwright
- [ ] Increase scheduler test coverage
- [ ] Add performance benchmarks
- [ ] Implement test data factories

### Long Term

- [ ] Visual regression testing
- [ ] Load testing suite
- [ ] Mutation testing
- [ ] Test coverage gates in CI (e.g., fail if coverage < 80%)

---

## Contributing

When adding new tests:

1. ✅ Place tests in appropriate directory (`unit/` or `integration/`)
2. ✅ Use descriptive test names
3. ✅ Use `cleanDb()` in `beforeEach` for integration tests
4. ✅ Use factory functions from `testUtils.ts`
5. ✅ Add tests to this documentation
6. ✅ Update coverage targets if needed

---

**Last Updated**: Based on test coverage run on latest commit
**Test Framework**: Vitest v4.0.16
**Coverage Tool**: v8

