# 🚨 Race Condition & ACID Compliance Analysis

## 📋 Executive Summary

This document provides a comprehensive analysis of the TripThread application's data consistency and race condition vulnerabilities. After analyzing all API endpoints, database workflows, transaction patterns, and external service integrations, **19 critical race conditions** have been identified, with **14 already fixed**, **3 from previous PRs requiring attention**, and **2 new from PR #35 requiring attention**.

**Current Security Status**: ✅ **74% Secure** (14/19 vulnerabilities addressed)

**Last Updated**: After PR #35 (UX enhancements: username login, ongoing trip redirect, floating bubble, enhanced logout, retry utilities, performance monitoring)

---

## ✅ **COMPLETED FIXES**

### 1. **Password Reset Token Race Condition** - FIXED ✅

- **Issue**: Multiple concurrent password reset requests could use the same token
- **Fix**: Implemented `SELECT FOR UPDATE` with atomic transaction
- **Files**: `src/lib/services/passwordReset.ts`
- **Status**: ✅ **SECURE**
- **Pattern Used**: Raw SQL `SELECT FOR UPDATE` lock + transaction
- **Impact**: Prevents token reuse and multiple password changes

### 2. **Previous Token Invalidation** - IMPLEMENTED ✅

- **Issue**: Old unused reset tokens remained valid when new ones were created
- **Fix**: Added `updateMany` to invalidate previous unused tokens before creating new ones
- **Files**: `src/lib/services/passwordReset.ts`
- **Status**: ✅ **SECURE**
- **Pattern Used**: Multi-step transaction ensuring only one valid token per user
- **Impact**: Prevents old tokens from being exploited

### 3. **Follow Request Acceptance** - SECURE ✅

- **File**: `src/app/api/follow/requests/[requestId]/accept/route.ts`
- **Implementation**: Uses `prisma.$transaction()` to atomically create follow and update request status
- **Status**: ✅ **SECURE**
- **Pattern Used**: Array transaction pattern
- **Impact**: Ensures follow is created if and only if request is updated

### 4. **Trip Participant Management (Add)** - SECURE ✅

- **File**: `src/app/api/trips/[id]/participants/route.ts` (POST handler)
- **Implementation**: Uses `prisma.$transaction()` with array pattern for participant creation and count increment
- **Status**: ✅ **SECURE**
- **Pattern Used**: Atomic increment for counter
- **Impact**: Participant count always matches actual participants

### 5. **Trip Participant Management (Remove)** - SECURE ✅

- **File**: `src/app/api/trips/[id]/participants/route.ts` (DELETE handler)
- **Implementation**: Uses `prisma.$transaction()` array pattern for deletion, count decrement, and pending request cleanup
- **Status**: ✅ **SECURE**
- **Pattern Used**: Multi-operation transaction
- **Impact**: Consistent state when removing participant with cascading cleanup

### 6. **Follow Request Creation (POST /follow/requests)** - FIXED ✅

- **File**: `src/app/api/follow/requests/route.ts` (POST handler)
- **Previous Issue**: Race condition between checking existing follow and creating new request
- **Fix**: Wrapped entire operation in `prisma.$transaction()` with all checks inside transaction
- **Status**: ✅ **SECURE**
- **Pattern Used**: Callback transaction with comprehensive checks
- **Impact**: Prevents duplicate follow requests

### 7. **Trip Join Request Creation** - FIXED ✅

- **File**: `src/lib/tripInvitation.ts` (`sendInvitation` method)
- **Previous Issue**: Multiple separate queries without transaction protection
- **Fix**: Entire `sendInvitation` method wrapped in `prisma.$transaction()`
- **Status**: ✅ **SECURE**
- **Pattern Used**: Callback transaction with error handling for P2002
- **Impact**: Prevents duplicate trip invitations

### 8. **Thread Entry Tagging** - FIXED ✅

- **File**: `src/app/api/trips/[id]/entries/route.ts` (POST handler)
- **Previous Issue**: Tag creation happened outside main transaction
- **Fix**: Tag creation moved inside transaction (lines 261-269)
- **Status**: ✅ **SECURE**
- **Pattern Used**: Tags created within same transaction as entry
- **Impact**: Prevents orphaned entries without tags

### 9. **Username/Email Uniqueness** - FIXED ✅

- **Files**: 
  - `src/app/api/auth/signup/route.ts` (email)
  - `src/app/api/users/me/route.ts` (username)
  - `src/app/api/users/[id]/route.ts` (username)
- **Previous Issue**: Check-then-insert pattern without transaction
- **Fix**: Removed pre-check, rely on database unique constraint with proper error handling via `handlePrismaUniqueError`
- **Status**: ✅ **SECURE**
- **Pattern Used**: Try-catch with Prisma error mapper
- **Impact**: Database enforces uniqueness, friendly error messages

### 10. **OAuth Account Linking Race Condition** - FIXED ✅

- **File**: `src/app/api/auth/link-google/route.ts`
- **Previous Issue**: Check for existing OAuth account and creation not atomic, allowing duplicate OAuth account creation attempts
- **Fix**: Wrapped OAuth account creation in `prisma.$transaction()` with double-check pattern inside transaction
- **Status**: ✅ **SECURE**
- **Pattern Used**: Transaction with double-check to prevent race condition
- **Impact**: Prevents duplicate OAuth account linking attempts

### 11. **OAuth Google Login Account Linking** - FIXED ✅

- **File**: `src/app/api/auth/google/route.ts`
- **Previous Issue**: When linking OAuth account to existing user by email, check and create operations not atomic
- **Fix**: Wrapped OAuth account creation in `prisma.$transaction()` with error handling for P2002 (unique constraint)
- **Status**: ✅ **SECURE**
- **Pattern Used**: Transaction with error handling for concurrent creation attempts
- **Impact**: Prevents duplicate OAuth account creation during Google login

### 12. **Profile Update Username Requirement Check** - FIXED ✅

- **File**: `src/app/api/users/me/route.ts` (PUT handler)
- **Previous Issue**: Username requirement check happened outside transaction, creating race window where username could change between check and update
- **Fix**: Moved username requirement check inside `prisma.$transaction()` along with the update operation
- **Status**: ✅ **SECURE**
- **Pattern Used**: Transaction with atomic check-and-update
- **Impact**: Ensures username requirement is checked with fresh data and update is atomic

### 13. **Code Quality: Dynamic Import Refactoring** - FIXED ✅

- **Files**: 
  - `src/app/api/auth/signup/route.ts`
  - `src/app/api/follow/requests/route.ts`
  - `src/app/api/users/[id]/route.ts`
  - `src/app/api/follow/[userId]/route.ts`
  - `src/lib/tripInvitation.ts`
- **Previous Issue**: Dynamic imports of `handlePrismaUniqueError` in catch blocks reduced performance and code clarity
- **Fix**: Converted all dynamic imports to static top-level imports
- **Status**: ✅ **IMPROVED**
- **Pattern Used**: Static imports for better performance and type safety
- **Impact**: Improved code maintainability, performance, and consistency

### 14. **Frontend Validation: Username Requirement** - FIXED ✅

- **File**: `mobile/lib/utils/validators.dart`
- **Previous Issue**: Username validation returned `null` when empty, making it optional when backend requires it
- **Fix**: Updated `validateUsername` to return error message when empty, making it required
- **Status**: ✅ **IMPROVED**
- **Pattern Used**: Consistent validation between frontend and backend
- **Impact**: Prevents invalid data submission and improves user experience

---

## 🔍 **IDENTIFIED RACE CONDITIONS & ACID VIOLATIONS**

### **HIGH PRIORITY** 🚨

#### 0. **Signup Route: Google-Only Account Reclaim Race Condition** - FIXED ✅

**File**: `src/app/api/auth/signup/route.ts` (POST handler, lines 18-113)

**Previous Issue**: Check for existing user, deletion of Google-only account, and new user creation were not atomic, creating race windows

**Fix**: Wrapped entire check-delete-create operation in a single `prisma.$transaction()` to ensure atomicity

```typescript
// Hash password before transaction (deterministic and fast operation)
const hashedPassword = await AuthService.hashPassword(password);

// Wrap check-delete-create in a single transaction to prevent race conditions
const user = await prisma.$transaction(async (tx) => {
  // Check for existing user INSIDE transaction
  const existingByEmail = await tx.user.findUnique({
    where: { email },
    select: { id: true, deletedAt: true, password: true, oauthAccounts: { select: { id: true } } },
  });

  if (existingByEmail) {
    if (existingByEmail.deletedAt == null) {
      const isGoogleOnly = existingByEmail.password == null && existingByEmail.oauthAccounts.length > 0;
      if (isGoogleOnly) {
        // Delete OAuth and soft-delete user atomically
        await tx.oAuthAccount.deleteMany({ where: { userId: existingByEmail.id } });
        await tx.user.update({
          where: { id: existingByEmail.id },
          data: { deletedAt: new Date(), email: `deleted_...`, ... },
        });
      } else {
        throw new Error("This email is already in use. Sign in with that account or use a different email.");
      }
    } else {
      // Free email for deleted user atomically
      await tx.user.update({
        where: { id: existingByEmail.id },
        data: { email: `deleted_...`, username: null },
      });
    }
  }
  
  // Create new user INSIDE same transaction
  return await tx.user.create({
    data: { email, password: hashedPassword, name, username },
  });
});
```

**Status**: ✅ **SECURE**
**Pattern Used**: Single transaction wrapping check-delete-create operations
**Impact**: Prevents duplicate user creation and ensures atomic account reclaim
**Fix Date**: After PR #34 review

---

#### 0b. **Google OAuth: Concurrent Sign-In OAuth Account Creation** - FIXED ✅

**File**: `src/app/api/auth/google/route.ts` (POST handler, lines 248-283)

**Previous Issue**: When handling concurrent sign-in (P2002 error), OAuth account creation happened outside transaction

**Fix**: Wrapped OAuth account check and creation in `prisma.$transaction()` to ensure atomicity

```typescript
// Use transaction to atomically check and create OAuth account if needed
const result = await prisma.$transaction(async (tx) => {
  const existingByEmail = await tx.user.findFirst({
    where: { email, deletedAt: null },
    include: { oauthAccounts: true },
  });
  
  if (!existingByEmail) {
    return null;
  }
  
  const hasGoogle = existingByEmail.oauthAccounts.some(
    (a) => a.provider === OAuthProvider.GOOGLE && a.providerUserId === sub
  );
  
  if (!hasGoogle) {
    try {
      await tx.oAuthAccount.create({
        data: {
          userId: existingByEmail.id,
          provider: OAuthProvider.GOOGLE,
          providerUserId: sub,
        },
      });
    } catch (error: any) {
      // OAuth already created by concurrent request (unique constraint violation)
      // This is expected in race conditions, continue to fetch user
    }
  }
  
  // Fetch user with updated OAuth accounts
  return await tx.user.findUnique({
    where: { id: existingByEmail.id },
    include: { oauthAccounts: true },
  });
});
```

**Status**: ✅ **SECURE**
**Pattern Used**: Transaction with error handling for concurrent OAuth account creation
**Impact**: Ensures atomic OAuth account linking in concurrent scenarios
**Fix Date**: After PR #34 review

---

### **HIGH PRIORITY** 🚨

#### 1. **Final Post Generation (End Trip)** - VULNERABLE ⚠️

**File**: `src/app/api/trips/[id]/end/route.ts` (POST handler, lines 58-110)

**Issue**: Final post generation happens OUTSIDE the transaction that updates trip status, creating a race window

```typescript
// Update trip status in a transaction
const updatedTrip = await prisma.$transaction(async (tx) => {
  return await tx.trip.update({
    where: { id: tripId },
    data: {
      status: TripStatus.ENDED,
      endDate: new Date(),
      updatedAt: new Date(),
    },
    // ... includes ...
  });
});

// RACE WINDOW: Final post generated AFTER transaction commits
// Another request could end the trip or modify data here
const finalPost = await TripFinalizerService.generateFinalPost(
  tripId,
  userId
);
```

**Race Scenario**:
1. Request A: Updates trip status to ENDED ✓ (transaction commits)
2. Request B: Updates trip status to ENDED ✓ (transaction commits) - duplicate
3. Request A: Generates final post ✓
4. Request B: Generates final post ✓ - **DUPLICATE FINAL POST** ❌
   - OR: Request B: Adds new thread entry
   - Request A: Generates final post with stale data ❌

**Risk Level**: **HIGH** - Duplicate final posts or stale data in final post
**Severity**: Data inconsistency, incomplete final posts, duplicate final posts

**Affected Records**:
- `tripFinalPost` table - possible duplicates (though unique constraint on tripId prevents)
- Final post content - may be based on stale thread entries
- User experience - incomplete or outdated final posts

**Current Protection**: `TripFinalizerService.generateFinalPost` checks for existing final post, but race window exists between trip update and final post check

**Recommended Fix**:
```typescript
const [updatedTrip, finalPost] = await prisma.$transaction(async (tx) => {
  // Update trip status
  const updated = await tx.trip.update({
    where: { id: tripId },
    data: {
      status: TripStatus.ENDED,
      endDate: new Date(),
      updatedAt: new Date(),
    },
    include: {
      threadEntries: {
        include: { media: true, place: true },
        orderBy: { createdAt: "asc" },
      },
      media: true,
    },
  });

  // Check if final post exists (inside transaction)
  const existing = await tx.tripFinalPost.findUnique({
    where: { tripId },
  });
  
  if (existing) {
    return [updated, existing];
  }

  // Generate final post inside transaction with fresh data
  const summaryText = buildSummary(updated);
  const curatedMedia = selectCuratedMedia(updated);
  const finalPost = await tx.tripFinalPost.create({
    data: {
      tripId,
      summaryText,
      curatedMedia,
      caption: generateDefaultCaption(updated),
      coverMediaUrl: curatedMedia[0] ?? updated.media.find(m => m.url)?.url ?? null,
      generationStatus: GenerationStatus.READY,
    },
  });

  return [updated, finalPost];
});
```

---

#### 2. **Media Storage Quota Tracking** - VULNERABLE ⚠️

**File**: `src/lib/cloudinary.ts` (`confirmUpload` method, lines 303-316)

**Issue**: Quota check happens OUTSIDE transaction, then media creation happens separately

```typescript
// OUTSIDE transaction - RACE WINDOW
if (USER_STORAGE_QUOTA_BYTES > 0) {
  const currentUsage = await prisma.media.aggregate({
    _sum: { size: true },
    where: { uploadedById: userId },
  });
  const usedBytes = currentUsage._sum.size ?? 0;
  if (usedBytes + data.bytes > USER_STORAGE_QUOTA_BYTES) {
    throw new ValidationError("Storage quota exceeded");
  }
}

// CREATE - Another upload could happen here, exceeding quota
const media = await prisma.media.create({
  data: {
    url: data.secure_url,
    publicId: data.public_id,
    size: data.bytes,
    uploadedById: userId,
    // ...
  },
});
```

**Race Scenario**:
1. Upload A: Checks quota - 4.8GB used, 200MB available ✓
2. Upload B: Checks quota - 4.8GB used, 200MB available ✓
3. Upload A: Creates media (200MB) - Total: 5.0GB ✓
4. Upload B: Creates media (200MB) - Total: 5.2GB ❌ **QUOTA EXCEEDED**

**Risk Level**: **HIGH** - Users can exceed storage quota
**Severity**: Storage quota bypass, potential cost overruns

**Affected Records**:
- `media` table - quota exceeded
- Cloudinary storage - over quota usage
- Billing - unexpected costs

**Recommended Fix**:
```typescript
const media = await prisma.$transaction(async (tx) => {
  // Check quota INSIDE transaction
  if (USER_STORAGE_QUOTA_BYTES > 0) {
    const currentUsage = await tx.media.aggregate({
      _sum: { size: true },
      where: { uploadedById: userId },
    });
    const usedBytes = currentUsage._sum.size ?? 0;
    if (usedBytes + data.bytes > USER_STORAGE_QUOTA_BYTES) {
      throw new ValidationError("Storage quota exceeded");
    }
  }

  // Create media inside same transaction
  return await tx.media.create({
    data: {
      url: data.secure_url,
      publicId: data.public_id,
      size: data.bytes,
      uploadedById: userId,
      // ...
    },
  });
});
```

---

#### 3. **Follow User (POST /follow/[userId])** - MOSTLY SECURE ✅

**File**: `src/app/api/follow/[userId]/route.ts` (POST handler, lines 111-283)

**Status**: ✅ **SECURE** - All checks and creation happen inside transaction

**Implementation**: User lookup, follow checks, and request creation all within `prisma.$transaction()`
- Checks followee existence inside transaction
- Checks existing follow inside transaction
- Checks existing requests inside transaction
- Creates follow/request inside transaction

**Risk Level**: **LOW** - Well protected by transaction
**Note**: Minor improvement possible by moving initial user lookup inside transaction, but current implementation is secure due to transaction protection.

---

#### 4. **Cache Get-Or-Set Race Condition** - VULNERABLE ⚠️

**File**: `src/lib/redis.ts` (`getOrSet` function, lines 30-69)

**Issue**: Classic cache stampede / thundering herd problem - multiple concurrent requests can all miss cache and trigger expensive operations

```typescript
export async function getOrSet<T>(
    key: string,
    getter: () => Promise<T>,
    ttl: number = DEFAULT_CACHE_TTL
): Promise<T> {
    // Try memory cache first
    const memValue = memoryCache.get(key) as T | undefined;
    if (memValue !== undefined) {
        return memValue;
    }

    if (redis) {
        // Try Redis cache next
        const cachedValue = await redis.get<RedisValue<T>>(key);
        if (cachedValue && cachedValue.timestamp + ttl > Date.now()) {
            memoryCache.set(key, cachedValue.data, ttl);
            return cachedValue.data;
        }
    }

    // RACE WINDOW: Multiple requests can reach here simultaneously
    // All will call getter() and set cache, wasting resources
    const value = await getter();

    // Update both caches
    if (value !== undefined && value !== null) {
        const redisValue: RedisValue<T> = {
            data: value,
            timestamp: Date.now()
        };
        if (redis) {
            await redis.set(key, redisValue, { ex: Math.floor(ttl / 1000) });
        }
        memoryCache.set(key, value, ttl);
    }

    return value;
}
```

**Race Scenario**:
1. Request A: Cache miss, calls `getter()` (expensive DB query)
2. Request B: Cache miss, calls `getter()` (expensive DB query) - **DUPLICATE WORK**
3. Request C: Cache miss, calls `getter()` (expensive DB query) - **DUPLICATE WORK**
4. All three set cache with same value - wasted resources

**Risk Level**: **MEDIUM** - Performance degradation, resource waste
**Severity**: Cache stampede can overwhelm database/external services

**Affected Operations**:
- Place searches (Mapbox API calls)
- Place resolution (database queries)
- Any expensive operation using `getOrSet`

**Recommended Fix** - Use mutex/lock for cache misses:
```typescript
export async function getOrSet<T>(
    key: string,
    getter: () => Promise<T>,
    ttl: number = DEFAULT_CACHE_TTL
): Promise<T> {
    // Try memory cache first
    const memValue = memoryCache.get(key) as T | undefined;
    if (memValue !== undefined) {
        return memValue;
    }

    if (redis) {
        // Try Redis cache next
        const cachedValue = await redis.get<RedisValue<T>>(key);
        if (cachedValue && cachedValue.timestamp + ttl > Date.now()) {
            memoryCache.set(key, cachedValue.data, ttl);
            return cachedValue.data;
        }
    }

    // Use mutex to prevent cache stampede
    return await withLock(`cache:${key}`, async () => {
        // Double-check cache after acquiring lock
        const memValue = memoryCache.get(key) as T | undefined;
        if (memValue !== undefined) {
            return memValue;
        }

        if (redis) {
            const cachedValue = await redis.get<RedisValue<T>>(key);
            if (cachedValue && cachedValue.timestamp + ttl > Date.now()) {
                memoryCache.set(key, cachedValue.data, ttl);
                return cachedValue.data;
            }
        }

        // Only one request will reach here
        const value = await getter();

        if (value !== undefined && value !== null) {
            const redisValue: RedisValue<T> = {
                data: value,
                timestamp: Date.now()
            };
            if (redis) {
                await redis.set(key, redisValue, { ex: Math.floor(ttl / 1000) });
            }
            memoryCache.set(key, value, ttl);
        }

        return value;
    });
}
```

---

#### 5. **Place Cache Invalidation Race Condition** - VULNERABLE ⚠️

**File**: `src/lib/place.ts` (`resolvePlace` function, lines 426-524)

**Issue**: Cache invalidation and place creation can race, leading to stale cache entries

```typescript
export async function resolvePlace(input: PlaceInput) {
  // Check cache
  const refResults = await cacheGetJsonBatch<string>(cacheKeys);
  
  // ... cache lookup logic ...
  
  // If cache miss, use mutex for creation
  return await withLock(`place:resolve:${spatialKey}`, async () => {
    // Check external ID
    if (input.externalId) {
      const existing = await prisma.place.findUnique({
        where: { externalId: input.externalId },
      });
      if (existing) {
        await cacheResults(existing, cacheKeys); // Cache set
        return existing;
      }
    }

    // Try spatial match
    const spatialMatches = await prisma.place.findMany({...});
    const match = spatialMatches.find((p) => arePlacesClose(p, input));
    if (match) {
      await cacheResults(match, cacheKeys); // Cache set
      return match;
    }

    // Create new place
    const created = await prisma.place.create({ data: placeData });
    
    // RACE WINDOW: Another request could invalidate cache here
    await cacheResults(created, cacheKeys); // Cache set
    return created;
  });
}
```

**Race Scenario**:
1. Request A: Cache miss, acquires lock, creates place, sets cache
2. Request B: Cache miss, waits for lock
3. Request A: Releases lock, cache set
4. Request C: Invalidates cache (e.g., place update)
5. Request B: Acquires lock, finds place exists, sets cache with potentially stale data

**Risk Level**: **MEDIUM** - Stale cache data, inconsistent place resolution
**Severity**: Users may see outdated place information

**Recommended Fix** - Ensure cache operations are atomic:
```typescript
return await withLock(`place:resolve:${spatialKey}`, async () => {
  // Double-check cache after acquiring lock
  const refResults = await cacheGetJsonBatch<string>(cacheKeys);
  // ... check cache again ...
  
  // Create place
  const created = await prisma.place.create({ data: placeData });
  
  // Set cache atomically (already using pipeline, which is good)
  await cacheResults(created, cacheKeys);
  return created;
});
```

**Note**: Current implementation uses mutex which helps, but cache invalidation timing can still cause issues.

---

#### 6. **Media Cleanup Orphaned Media** - POTENTIAL ISSUE ⚠️

**File**: `src/lib/cloudinary.ts` (`cleanupOrphanedMedia` method, lines 341-365)

**Issue**: Cleanup happens asynchronously after media confirmation, creating potential race conditions

```typescript
// In confirmUpload route
const { media } = await CloudinaryService.confirmUpload({...}, userId);

// OUTSIDE transaction - async cleanup
await CloudinaryService.cleanupOrphanedMedia(userId);
```

**Race Scenario**:
1. Upload A: Confirms media, creates Media record
2. Upload B: Confirms media, creates Media record
3. Upload A: Cleanup runs, finds media without tripId (from Upload A)
4. Upload B: Cleanup runs, finds media without tripId (from Upload B)
5. Both cleanup operations may delete media that's about to be used

**Risk Level**: **LOW-MEDIUM** - Media may be deleted before being attached to trip/entry
**Severity**: Orphaned media cleanup may be too aggressive

**Current Protection**: Cleanup only targets media older than 24 hours, which helps
**Recommendation**: Ensure cleanup doesn't run too frequently or consider moving to scheduled job

---

#### 7. **Cache Set Operations (Memory + Redis)** - MINOR ISSUE ⚠️

**File**: `src/lib/cache.ts` (`cacheSetJson` function, lines 534-574)

**Issue**: Memory cache and Redis cache updated separately, potential inconsistency

```typescript
export async function cacheSetJson<T = any>(
  key: string,
  value: T,
  ttlSeconds?: number
): Promise<boolean> {
  // Set in Redis
  const payload = ttlSeconds
    ? ["setex", key, ttlSeconds, stringValue]
    : ["set", key, stringValue];
  const result = await upstashFetch<string | string[]>("pipeline", [payload]);

  // RACE WINDOW: Redis set succeeds, but memory cache update fails
  // Or: Memory cache updated but Redis fails
  if (success) {
    memoryCache.set(key, {
      value: stringValue,
      expiresAt: Date.now() + (ttlSeconds ? ttlSeconds * 1000 : DEFAULT_MEMORY_TTL),
    });
  }
}
```

**Race Scenario**:
1. Request A: Sets cache in Redis ✓
2. Request B: Sets cache in Redis ✓ (overwrites A)
3. Request A: Sets memory cache with old value ❌
4. Memory cache now has stale data

**Risk Level**: **LOW** - Cache inconsistency, but not data corruption
**Severity**: Minor - cache may be temporarily inconsistent between memory and Redis

**Current Mitigation**: Memory cache TTL is shorter, so inconsistencies self-correct
**Recommendation**: Consider making operations more atomic, but current implementation is acceptable for cache layer

---

#### 8. **Trip Status Auto-Update (Scheduler)** - MOSTLY SECURE ✅

**File**: `scheduler/src/tripStatus.ts` (`updateTripStatuses` function, lines 104-201)

**Status**: ✅ **MOSTLY SECURE** - Each trip update wrapped in individual transaction

**Current Implementation**:
- Each trip ending is processed in its own transaction
- Final post creation and status update are atomic per trip
- Final post existence check happens inside transaction
- Thread entries fetched inside transaction for fresh data

**Remaining Issue**: Final post generation logic in scheduler differs from manual end trip logic
- Scheduler uses simpler summary generation
- Manual end uses `TripFinalizerService` with more sophisticated logic
- **Recommendation**: Use same `TripFinalizerService` in scheduler for consistency

**Risk Level**: **LOW** - Well protected, but logic inconsistency
**Severity**: Low - functional but inconsistent final post quality

---

#### 9. **Trip Entry Creation (Media Validation)** - MOSTLY SECURE ✅

**File**: `src/app/api/trips/[id]/entries/route.ts` (POST handler, lines 197-270)

**Status**: ✅ **SECURE** - Media validation re-checked inside transaction

**Current Implementation**:
- Initial media check outside transaction (for early validation)
- **Media re-validated inside transaction** (lines 199-212) - prevents TOCTOU
- Tags created inside transaction (lines 261-269)
- Entry count updated inside transaction

**Risk Level**: **LOW** - Well protected by transaction with re-validation
**Note**: Initial check outside transaction is acceptable for early error return, as transaction re-validates

---

### **MEDIUM PRIORITY** ⚠️

#### 10. **Final Post Update/Publish Race Condition** - POTENTIAL ISSUE ⚠️

**File**: `src/lib/services/tripFinalizer.ts` (`updateFinalPost` and `publishFinalPost` methods)

**Issue**: Check-then-update pattern without transaction protection

```typescript
// updateFinalPost - lines 117-179
static async updateFinalPost(tripId: string, updates: FinalPostUpdates) {
  // Check if published OUTSIDE any protection
  const finalPost = await prisma.tripFinalPost.findUnique({
    where: { tripId },
  });
  if (finalPost.isPublished) {
    throw new ConflictError("Published posts cannot be edited");
  }
  
  // RACE WINDOW: Another request could publish here
  return prisma.tripFinalPost.update({
    where: { tripId },
    data: { ...updates, generationStatus: GenerationStatus.READY },
  });
}

// publishFinalPost - lines 181-244
static async publishFinalPost(tripId: string, userId: string) {
  // Multiple checks OUTSIDE transaction
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    include: { finalPost: true },
  });
  if (trip.finalPost.isPublished) {
    throw new ConflictError("Final post has already been published");
  }
  
  // RACE WINDOW: Another request could publish here
  return prisma.tripFinalPost.update({
    where: { tripId },
    data: {
      isPublished: true,
      publishedAt: new Date(),
      generationStatus: GenerationStatus.PUBLISHED,
    },
  });
}
```

**Race Scenario**:
1. Request A: Checks - not published ✓
2. Request B: Checks - not published ✓
3. Request A: Publishes ✓
4. Request B: Publishes ✓ - **DUPLICATE PUBLISH** ❌ (though unique constraint prevents)

**Risk Level**: **LOW** - Database unique constraint on tripId prevents duplicate final posts
**Severity**: Low - constraint prevents actual duplicates, but error handling could be better

**Recommended Fix** - Wrap in transaction:
```typescript
static async publishFinalPost(tripId: string, userId: string) {
  return await prisma.$transaction(async (tx) => {
    const trip = await tx.trip.findUnique({
      where: { id: tripId },
      include: { finalPost: true },
    });
    // All checks inside transaction
    if (!trip) throw new NotFoundError("Trip not found");
    if (trip.userId !== userId) throw new AuthorizationError(...);
    if (!trip.finalPost) throw new NotFoundError("Final post not found");
    if (trip.finalPost.isPublished) {
      throw new ConflictError("Final post has already been published");
    }
    // Validation checks...
    
    // Update inside transaction
    return await tx.tripFinalPost.update({
      where: { tripId },
      data: {
        isPublished: true,
        publishedAt: new Date(),
        generationStatus: GenerationStatus.PUBLISHED,
      },
    });
  });
}
```

---

#### 11. **Media Upload Quota Tracking** - POTENTIAL ISSUE ⚠️

**File**: `src/app/api/media/confirm/route.ts` (lines 35-65)

**Issue**: Trip access check happens OUTSIDE transaction, then media creation happens separately

```typescript
// OUTSIDE transaction
if (tripId) {
  const trip = await prisma.trip.findFirst({
    where: {
      id: tripId,
      OR: [
        { userId: request.user!.userId },
        { participants: { some: { userId: request.user!.userId } } },
      ],
    },
  });
  if (!trip) return error("Trip not found or access denied");
}

// RACE WINDOW: User could be removed from trip here
// Or trip could be deleted
const { media } = await CloudinaryService.confirmUpload({
  ...cloudinaryPayload,
  tripId,
  usage,
}, request.user!.userId);
```

**Race Scenario**:
1. Check: User is participant ✓
2. User removed from trip
3. Media created with tripId ❌ - Media attached to trip user no longer has access to

**Risk Level**: **LOW-MEDIUM** - Media attached to trip user can't access
**Severity**: Low - Media orphaned but not security issue (user can't see it)

**Current Protection**: Media creation doesn't fail if trip access changes, but media becomes inaccessible
**Recommendation**: Consider re-checking trip access inside `confirmUpload` transaction, but current behavior is acceptable

---

#### 12. **Cloudinary Delete Media Race Condition** - POTENTIAL ISSUE ⚠️

**File**: `src/lib/cloudinary.ts` (`deleteMedia` method, lines 335-339)

**Issue**: Cloudinary deletion and database deletion not atomic

```typescript
static async deleteMedia(publicId: string): Promise<void> {
  ensureConfigured();
  await cloudinary.uploader.destroy(publicId); // External API call
  await prisma.media.deleteMany({ where: { publicId } }); // DB deletion
}
```

**Race Scenario**:
1. Delete A: Deletes from Cloudinary ✓
2. Delete B: Deletes from Cloudinary ✓ (may fail if already deleted)
3. Delete A: Deletes from DB ✓
4. Delete B: Deletes from DB ✓ - **ORPHANED DB RECORD** if Cloudinary delete failed

**Risk Level**: **LOW** - Orphaned database records, but not critical
**Severity**: Low - Database records without Cloudinary assets (cleanup job can handle)

**Current Protection**: `deleteMany` is idempotent
**Recommendation**: Consider transaction-like behavior, but current implementation acceptable

---

#### 13. **SendGrid Email Race Conditions** - LOW PRIORITY ℹ️

**File**: Email sending operations (password reset, notifications)

**Issue**: Email sending is fire-and-forget, no idempotency checks

**Risk Level**: **LOW** - Users may receive duplicate emails
**Severity**: Low - UX issue, not data integrity

**Current Status**: Acceptable - email sending is idempotent by nature (external service)
**Recommendation**: Consider rate limiting per user per email type, but not critical

---

### **LOW PRIORITY** ℹ️

#### 14. **Trip Participant Count Mismatch** - EDGE CASE ⚠️

**File**: `src/app/api/trips/[id]/participants/route.ts`

**Issue**: `participantCount` is a denormalized counter that could drift if transaction fails mid-operation

```typescript
// Atomic operations (good), but if process crashes mid-transaction:
const [participant, _] = await prisma.$transaction([
  prisma.tripParticipant.create({...}),
  prisma.trip.update({
    where: { id: tripId },
    data: { participantCount: { increment: 1 } }
  }),
]);
// If crash happens between create and update, count is wrong
```

**Current Status**: ✅ **PROTECTED** - Transaction ensures atomicity
**Severity**: Low - counter can be reconciled, transaction prevents actual loss

**Monitoring Recommendation**:
```typescript
// Periodic reconciliation job
const actualCount = await prisma.tripParticipant.count({
  where: { tripId }
});
const trip = await prisma.trip.findUnique({ where: { id: tripId } });
if (actualCount !== trip.participantCount) {
  // Log discrepancy
  // Optionally auto-correct
}
```

---

#### 15. **User Account Deletion (Cascading Deletes)** - PROTECTED ⚠️

**File**: `src/app/api/users/me/route.ts` (DELETE handler, lines 125-175)

**Issue**: Complex deletion with cascading operations in a single transaction

```typescript
await prisma.$transaction(async (tx) => {
  // Many delete operations in sequence
  await tx.jWTRefreshToken.deleteMany({...});
  await tx.oAuthAccount.deleteMany({...});
  // ... 10 more delete operations ...
  await tx.user.update({...});
});
```

**Current Status**: ✅ **PROTECTED** - Single transaction ensures atomicity
**Severity**: Low - If transaction rolls back, all deletes are undone
**Risk**: Long-running transaction could lock multiple tables

**Monitoring Recommendation**:
```typescript
// Monitor transaction duration
const startTime = Date.now();
await prisma.$transaction(async (tx) => {
  // ...
});
const duration = Date.now() - startTime;
if (duration > 5000) {
  console.warn(`Long account deletion: ${duration}ms`);
}
```

---

## 🛠️ **COMPREHENSIVE FIX IMPLEMENTATION PLAN**

### **Phase 1: Critical Race Conditions (URGENT - Week 1)**

Priority fixes that directly impact data integrity:

#### Task 1.1: Fix Final Post Generation (End Trip)
- **File**: `src/app/api/trips/[id]/end/route.ts`
- **Change**: Move final post generation inside transaction with trip update
- **Estimated Effort**: 1 hour
- **Risk**: Medium - affects trip ending flow
- **Impact**: Prevents duplicate final posts and stale data

#### Task 1.2: Fix Media Quota Tracking
- **File**: `src/lib/cloudinary.ts` (`confirmUpload` method)
- **Change**: Move quota check inside transaction with media creation
- **Estimated Effort**: 45 minutes
- **Risk**: Low - isolated service method
- **Impact**: Prevents quota bypass

#### Task 1.3: Fix Cache Get-Or-Set Stampede
- **File**: `src/lib/redis.ts` (`getOrSet` function)
- **Change**: Add mutex/lock for cache misses to prevent thundering herd
- **Estimated Effort**: 1 hour
- **Risk**: Low - cache layer only
- **Impact**: Prevents resource waste and API overload

**Phase 1 Total Effort**: ~2.75 hours

---

### **Phase 2: Final Post Service Improvements (Week 1-2)**

#### Task 2.1: Fix Final Post Update/Publish Race Conditions
- **File**: `src/lib/services/tripFinalizer.ts`
- **Change**: Wrap `updateFinalPost` and `publishFinalPost` in transactions
- **Estimated Effort**: 45 minutes
- **Risk**: Low - service layer only

#### Task 2.2: Unify Final Post Generation Logic
- **Files**: 
  - `src/app/api/trips/[id]/end/route.ts`
  - `scheduler/src/tripStatus.ts`
- **Change**: Use `TripFinalizerService.generateFinalPost` in both places
- **Estimated Effort**: 30 minutes
- **Risk**: Low - improves consistency

**Phase 2 Total Effort**: ~1.25 hours

---

### **Phase 3: Database Schema Enhancements (Week 2)**

#### Task 2.1: Add Missing Unique Constraints
```sql
-- Already exists
ALTER TABLE users ADD CONSTRAINT users_email_unique UNIQUE (email);
ALTER TABLE users ADD CONSTRAINT users_username_unique UNIQUE (username);

-- Verify these exist
ALTER TABLE follows ADD CONSTRAINT follows_unique UNIQUE (followerId, followeeId);
ALTER TABLE follow_requests ADD CONSTRAINT follow_requests_unique UNIQUE (followerId, followeeId);
ALTER TABLE trip_join_requests ADD CONSTRAINT trip_join_requests_unique UNIQUE (tripId, receiverId);
```

**Estimated Effort**: 30 minutes

---

### **Phase 4: Transaction Wrapping (Week 2-3)**

#### Task 4.1: Place Cache Invalidation
- **File**: `src/lib/place.ts`
- **Change**: Improve cache invalidation timing and atomicity
- **Estimated Effort**: 30 minutes
- **Risk**: Low - cache layer only

**Phase 4 Total Effort**: ~30 minutes

---

### **Phase 5: Error Handling Improvements (Week 3)**

#### Task 5.1: Standardize Unique Constraint Error Handling
- Create utility function for Prisma error handling
- Apply to all endpoints with unique constraints

```typescript
// utils/prismaErrors.ts
export function handleUniqueConstraintError(error: any, fieldNames: Record<string, string>) {
  if (error.code === "P2002") {
    const field = error.meta?.target?.[0];
    const friendlyName = fieldNames[field] || field;
    return `${friendlyName} already exists or is taken`;
  }
  return null;
}
```

**Estimated Effort**: 2 hours

---

### **Phase 6: Testing & Validation (Week 4)**

#### Task 5.1: Load Testing
- Concurrent request simulation for all critical endpoints
- Measure race condition occurrence

#### Task 5.2: Constraint Validation
- Verify unique constraints work as expected
- Test error handling paths

#### Task 5.3: Integration Testing
- Test complete user workflows
- Verify no regressions

**Estimated Effort**: 4-8 hours depending on automation level

---

## 📊 **DETAILED AUDIT: Current Transaction Coverage**

| Feature | Endpoint | Current Status | Transaction Type | Risk Level |
|---------|----------|----------------|------------------|-----------|
| Follow Request Accept | `/follow/requests/[id]/accept` | ✅ SECURE | Array transaction | LOW |
| Follow/Unfollow | `/follow/[userId]` | ✅ SECURE | Full transaction | LOW |
| Follow Request Send | `/follow/requests` | ✅ SECURE | Full transaction | LOW |
| Trip Participant Add | `/trips/[id]/participants` (POST) | ✅ SECURE | Array transaction | LOW |
| Trip Participant Remove | `/trips/[id]/participants` (DELETE) | ✅ SECURE | Array transaction | LOW |
| Trip Join Request Send | `/trips/[id]/invites` | ✅ SECURE | Full transaction | LOW |
| Trip Join Request Accept | `/trips/[id]/invites/accept` | ✅ SECURE | Callback transaction | LOW |
| Thread Entry Create | `/trips/[id]/entries` (POST) | ✅ SECURE | Tx with tags inside | LOW |
| Thread Entry List | `/trips/[id]/entries` (GET) | ✅ SECURE | Read-only | LOW |
| Trip End | `/trips/[id]/end` | ⚠️ PARTIALLY SECURE | Tx but final post outside | MEDIUM |
| Trip Final Post Get | `/trips/[id]/final-post` (GET) | ✅ SECURE | Read-only | LOW |
| Trip Final Post Update | `/trips/[id]/final-post` (PUT) | ⚠️ PARTIALLY SECURE | No transaction | LOW |
| Trip Final Post Publish | `/trips/[id]/publish` (POST) | ⚠️ PARTIALLY SECURE | No transaction | LOW |
| Trip Create | `/trips` (POST) | ✅ SECURE | Callback transaction | LOW |
| User Profile Update | `/users/me` (PUT) | ✅ SECURE | Transaction + Error handling | LOW |
| User Profile Update | `/users/[id]` (PUT) | ✅ SECURE | Error handling | LOW |
| OAuth Account Link | `/auth/link-google` (POST) | ✅ SECURE | Transaction | LOW |
| OAuth Google Login | `/auth/google` (POST) | ✅ SECURE | Transaction | LOW |
| User Signup | `/auth/signup` | ✅ SECURE | Error handling | LOW |
| User Account Delete | `/users/me` (DELETE) | ✅ SECURE | Single transaction | LOW |
| Password Reset | `resetWithToken()` | ✅ SECURE | SELECT FOR UPDATE | LOW |
| Media Upload Confirm | `/media/confirm` (POST) | ⚠️ PARTIALLY SECURE | Quota check outside | MEDIUM |
| Media Delete | `/media/delete` (POST) | ✅ MOSTLY SECURE | External + DB | LOW |
| Scheduler Trip Status | `updateTripStatuses()` | ✅ MOSTLY SECURE | Per-trip transaction | LOW |
| Place Resolution | `resolvePlace()` | ✅ MOSTLY SECURE | Mutex lock | LOW |
| Cache Get-Or-Set | `getOrSet()` | ⚠️ VULNERABLE | No mutex | MEDIUM |

**Summary Statistics**:
- ✅ **SECURE**: 18 endpoints/services (78%)
- ⚠️ **PARTIALLY SECURE**: 4 endpoints/services (17%)
- ❌ **VULNERABLE**: 1 service (4%)
- ⚠️ **POTENTIAL ISSUES**: 0 edge cases (0%)

---

## 🔒 **SECURITY IMPACT ASSESSMENT**

### **Current Vulnerabilities**

| Vulnerability | Impact | Exploitability | Affected Records | Status |
|---------------|--------|-----------------|------------------|--------|
| Final Post Generation Race | Duplicate/stale final posts | Medium | `tripFinalPost` table | ⚠️ TO FIX |
| Media Quota Bypass | Storage quota exceeded | Medium | `media` table, Cloudinary | ⚠️ TO FIX |
| Cache Stampede | Resource waste, API overload | Low | External APIs (Mapbox) | ⚠️ TO FIX |
| Final Post Update Race | Concurrent publish attempts | Low | `tripFinalPost` table | ⚠️ TO FIX |
| Place Cache Invalidation | Stale cache data | Low | Cache layer | ⚠️ TO FIX |
| Media Cleanup Timing | Orphaned media | Low | `media` table | ✅ ACCEPTABLE |
| Cloudinary Delete Race | Orphaned DB records | Low | `media` table | ✅ ACCEPTABLE |

### **Fixed Vulnerabilities**

| Vulnerability | Status | Protection Method | Impact Reduction |
|---------------|--------|-------------------|------------------|
| Follow Request Spam | ✅ FIXED | Transaction + Unique Constraint | 100% |
| Trip Invitation Spam | ✅ FIXED | Transaction + Unique Constraint | 100% |
| Duplicate Username | ✅ FIXED | Error Handling + Unique Constraint | 100% |
| Duplicate Email | ✅ FIXED | Error Handling + Unique Constraint | 100% |
| Orphaned Media Tags | ✅ FIXED | Transaction Inclusion | 100% |
| Thread Entry Media Validation | ✅ FIXED | Re-validation inside transaction | 100% |
| Follow User Race | ✅ FIXED | Full transaction protection | 100% |

---

## 🛠️ **RECOMMENDED DATABASE ENHANCEMENTS**

### 1. **Add Unique Constraints** (Already exist, verify)

```prisma
model FollowRequest {
  followerId String
  followeeId String
  status     FollowRequestStatus

  @@unique([followerId, followeeId]) // Current: only per status
  @@map("follow_requests")
}

model TripJoinRequest {
  tripId    String
  receiverId String

  @@unique([tripId, receiverId]) // Verify this exists
  @@map("trip_join_requests")
}
```

### 2. **Add Indexes for Common Queries**

```prisma
model FollowRequest {
  @@index([followeeId, status])
  @@index([followerId, status])
}

model TripJoinRequest {
  @@index([receiverId, status])
  @@index([tripId, status])
}

model Trip {
  @@index([userId, status])
  @@index([endDate, status])
}
```

### 3. **Add Check Constraints**

```sql
-- Ensure trip endDate >= startDate
ALTER TABLE trips ADD CONSTRAINT trips_end_after_start 
CHECK (end_date >= start_date);

-- Ensure participant count >= 1
ALTER TABLE trips ADD CONSTRAINT trips_min_participants 
CHECK (participant_count >= 1);
```

---

## 📈 **ACID Compliance Checklist (Post-Fixes)**

### **Atomicity** ✅ → 🔄 (Significantly Improved)

- [x] Password reset (FIXED)
- [x] Trip participant management (GOOD)
- [x] Trip entry creation (GOOD - tags inside transaction)
- [x] Follow request acceptance (GOOD)
- [x] Follow request creation (FIXED)
- [x] Trip join request creation (FIXED)
- [x] Username/email updates (FIXED - error handling)
- [x] Thread entry tagging (FIXED)
- [x] Follow user operations (FIXED)
- [ ] **Final post generation** (TO FIX - move inside transaction)
- [ ] **Media quota tracking** (TO FIX - move inside transaction)
- [x] Trip status updates (MOSTLY GOOD - per-trip transactions)

### **Consistency** ✅ (Strong)

- [x] Foreign key constraints enforced
- [x] Enum constraints enforced
- [x] Unique constraints for email, username, follows (VERIFIED)
- [x] Email error handling standardized (FIXED - `handlePrismaUniqueError`)
- [x] Username error handling standardized (FIXED - `handlePrismaUniqueError`)
- [x] Final post unique constraint (tripId unique)

### **Isolation** ✅ (Excellent)

- [x] Password reset (FIXED with SELECT FOR UPDATE)
- [x] Follow endpoints (FIXED with full transactions)
- [x] Trip participants (GOOD with tx)
- [x] Follow requests (FIXED)
- [x] Trip join requests (FIXED)
- [x] Thread entries (GOOD with re-validation)
- [ ] **Final post operations** (TO IMPROVE - add transactions)
- [ ] **Media quota** (TO IMPROVE - add transaction)

### **Durability** ✅ (Excellent)

- [x] All operations properly committed to PostgreSQL
- [x] No rollback issues identified
- [x] Backup strategy in place (assumed)

---

## 🎯 **IMPLEMENTATION ROADMAP**

```
Week 1: Critical Fixes
├── Mon-Tue: Fix Follow Request & Trip Invitation creation
├── Wed: Fix Email & Username uniqueness
└── Thu-Fri: Testing & Code Review

Week 2: Database & Transaction Updates
├── Mon-Tue: Schema verification & constraint additions
├── Wed-Thu: Transaction wrapping for follow endpoints
└── Fri: Code Review

Week 3: Advanced Fixes
├── Mon-Tue: Thread entry tagging fix
├── Wed: Trip final post creation fix
├── Thu: Scheduler trip status fix
└── Fri: Code Review & Integration Testing

Week 4: Validation & Deployment
├── Mon-Tue: Load testing & Race condition simulation
├── Wed: Performance benchmarking
├── Thu: Production deployment planning
└── Fri: Post-deployment monitoring
```

---

## 📝 **MONITORING & ALERTS**

### **Metrics to Track**

1. **Constraint Violation Rate**
   ```
   SELECT COUNT(*) as violations
   FROM pg_stat_statements
   WHERE query LIKE '%P2002%'
   GROUP BY query
   ```

2. **Transaction Duration**
   ```
   SELECT avg(execution_time), max(execution_time)
   FROM pg_stat_statements
   WHERE query LIKE '%$transaction%'
   ```

3. **Duplicate Record Incidents**
   ```
   SELECT table_name, count(*) as duplicates
   FROM pg_indexes
   WHERE constraint_type = 'UNIQUE'
   GROUP BY table_name
   ```

### **Alert Thresholds**

- Unique constraint violations > 10/hour → ALERT
- Transaction avg duration > 1s → INVESTIGATE
- Duplicate records detected → CRITICAL

---

## 🚀 **DEPLOYMENT CHECKLIST**

- [ ] All race condition fixes implemented
- [ ] Database constraints verified
- [ ] Error handling standardized
- [ ] Unit tests added for each fix
- [ ] Load testing completed (10k concurrent requests)
- [ ] Race condition test suite passes
- [ ] Performance benchmarks within acceptable range
- [ ] Code review approved
- [ ] Documentation updated
- [ ] Rollback plan prepared
- [ ] Monitoring alerts configured
- [ ] Production deployment scheduled
- [ ] Post-deployment validation completed

---

## 📚 **Key References & Patterns**

### **Prisma Transaction Patterns**

1. **Array Transaction** (Best for simple operations):
   ```typescript
   await prisma.$transaction([
     prisma.model1.create(...),
     prisma.model2.update(...),
   ]);
   ```

2. **Callback Transaction** (Best for conditional logic):
   ```typescript
   await prisma.$transaction(async (tx) => {
     const result = await tx.model.findUnique(...);
     if (result) {
       await tx.model.delete(...);
     }
   });
   ```

3. **SELECT FOR UPDATE** (Best for read-before-write):
   ```typescript
   await prisma.$transaction(async (tx) => {
     const result = await tx.$queryRaw`
       SELECT * FROM model WHERE id = ${id} FOR UPDATE
     `;
     // Modifications safe here
   });
   ```

### **Error Handling**

```typescript
try {
  await prisma.user.create({...});
} catch (error) {
  if (error.code === "P2002") {
    // Unique constraint violation
    const field = error.meta?.target?.[0];
    console.error(`${field} already exists`);
  } else if (error.code === "P2025") {
    // Record not found
    console.error("Record not found");
  }
}
```

---

## 🔍 **Conclusion**

The application has made **significant progress** with **9 out of 16 critical operations now protected** by transactions or proper error handling. The codebase shows strong ACID compliance in most areas, with **7 remaining issues** that require attention.

**Key Improvements Since Last Review**:
- ✅ Follow request creation now uses transactions
- ✅ Trip invitation creation now uses transactions  
- ✅ Thread entry tagging moved inside transactions
- ✅ Username/email uniqueness uses proper error handling
- ✅ Follow user operations fully transactional
- ✅ OAuth account linking now uses transactions (PR #34)
- ✅ Profile update username requirement check now atomic (PR #34)
- ✅ DRY violation fixed - /users/me now uses validation schema (PR #34)
- ✅ Static imports for error handlers (PR #34)
- ✅ Frontend username validation now required (PR #34)

**Remaining High-Priority Issues**:
1. Final post generation race condition (end trip route)
2. Media quota tracking race condition
3. Cache stampede in getOrSet function

**Recommended Action**: Implement Phase 1 fixes immediately (2.75 hours work) to eliminate the remaining critical race conditions affecting final posts and media quota.

**Estimated Total Effort for Complete Fix**: 6-8 hours across 2-3 weeks with proper testing and validation.

**Overall Security Status**: ✅ **75% Secure** → Target: **90%+ Secure** after Phase 1 fixes

**Recent Improvements (PR #34 - Profile Page Bio & Username Fixes)**:
- ✅ Fixed OAuth account linking race condition (`/auth/link-google`)
- ✅ Fixed OAuth Google login account linking race condition (`/auth/google`)
- ✅ Fixed profile update username requirement check race condition (`/users/me`)
- ✅ Improved DRY compliance by using shared `updateProfileSchema` validation schema
- ✅ Enhanced ACID compliance for profile updates with transaction protection
- ✅ Refactored dynamic imports to static imports for better performance and maintainability
- ✅ Updated frontend validators to make username required (consistent with backend)
- ✅ Fixed location validation to handle location objects correctly (not just strings)

**PR #34 Merge Readiness**: ✅ **READY TO MERGE**

**Status**: All race conditions have been addressed, including the ones identified during review. The PR is fully secure and ready for merge.

**Completed Fixes**:
1. ✅ All intended race condition fixes (OAuth linking, profile updates) are correct and secure
2. ✅ Signup route race condition fixed (wrapped in single transaction)
3. ✅ Google OAuth concurrent sign-in race condition fixed (wrapped in transaction)
4. ✅ Code quality improvements are solid (static imports, shared validation)
5. ✅ Frontend-backend validation consistency achieved

**Impact Assessment**:
- **High-priority fixes**: All addressed ✅
- **Race conditions**: All identified issues fixed ✅
- **Overall**: PR is fully secure and ready to merge

---

## 🔍 **PR #35 REVIEW: UX Enhancements**

**Review Date**: 2026-02-21  
**PR**: #35 - Feat ux enhancements  
**Status**: ✅ **SECURE** - No race conditions or transaction violations identified

### **📋 Changes Summary**

PR #35 introduces three main UX enhancements:

1. **Username Logic Enhancements**: Unicode lookalike normalization (Cyrillic/Greek → ASCII)
2. **Thread Screen Auto-Open**: Automatic navigation to thread screen when ongoing trip exists
3. **Floating Bubble Button**: Draggable navigation button for quick access to thread/home

### **🔒 Security & Race Condition Analysis**

#### **1. Username Logic Enhancements** - ✅ **SECURE**

**Backend Changes**:
- Username normalization function `normalizeUsernameToAscii()` in `src/lib/validation.ts`
- Already protected by transaction in profile update endpoint (PR #34)
- Unique constraint on username field prevents duplicates

**Frontend Changes**:
- Matching normalization in `mobile/lib/utils/validators.dart`
- Client-side validation only, no race conditions

**Status**: ✅ **NO ISSUES** - Username updates already secured in PR #34 with transaction protection

---

#### **2. Thread Screen Auto-Open** - ✅ **MOSTLY SECURE** (Frontend-only)

**Implementation**:
- `HomeScreen` checks for ongoing trip on initialization
- Uses `hasCompletedInitialOngoingTripRedirect` flag to prevent redirect loops
- Calls `GET /trips/status` endpoint to fetch current trip

**Backend Endpoint Analysis** (`GET /api/trips/status`):
```typescript
// Read-only query - no race conditions
const trip = await prisma.trip.findFirst({
  where: { userId, status: "ONGOING" },
  // ...
});
```

**Potential Issues**:
- ⚠️ **MINOR**: `findFirst` could return different trips if multiple ongoing trips exist (though business logic prevents this)
- ⚠️ **MINOR**: No database constraint preventing multiple ongoing trips per user
- ✅ **MITIGATED**: Business logic in trip creation (`validateTripStatus`) prevents multiple ongoing trips

**Frontend State Management**:
- `TripProvider.loadCurrentTrip()` is async but not protected against concurrent calls
- ⚠️ **MINOR**: Multiple concurrent calls could cause state inconsistency (UI-only, no data corruption)

**Recommendation**:
```dart
// Add guard to prevent concurrent loads
bool _isLoadingCurrentTrip = false;

Future<void> loadCurrentTrip() async {
  if (_isLoadingCurrentTrip) return; // Prevent concurrent calls
  _isLoadingCurrentTrip = true;
  try {
    // ... existing code ...
  } finally {
    _isLoadingCurrentTrip = false;
  }
}
```

**Status**: ✅ **ACCEPTABLE** - Minor frontend state management improvement recommended, but no data integrity issues

---

#### **3. Floating Bubble Button** - ✅ **SECURE** (Pure UI)

**Implementation**:
- Pure UI component (`FloatingTripNavButton`)
- No backend interactions
- State persisted in memory only (`_savedBubblePosition`)

**Status**: ✅ **NO ISSUES** - Pure frontend component, no race conditions

---

### **📊 Transaction & Database Analysis**

#### **Backend Endpoints Reviewed**

| Endpoint | Method | Transaction | Race Condition Risk | Status |
|----------|--------|-------------|---------------------|--------|
| `/api/trips/status` | GET | N/A (read-only) | None | ✅ SECURE |
| `/api/users/me` | PUT | ✅ Yes (PR #34) | None | ✅ SECURE |
| `/api/auth/signup` | POST | ✅ Yes (PR #34) | None | ✅ SECURE |

**Summary**: All backend operations are either read-only or already protected by transactions from previous PRs.

---

### **⚠️ Areas for Improvement**

#### **1. Frontend State Management (Low Priority)**

**Issue**: `TripProvider.loadCurrentTrip()` lacks concurrency protection

**Impact**: Low - UI state inconsistency only, no data corruption

**Recommendation**: Add loading flag to prevent concurrent calls (see code above)

---

#### **2. Database Constraint (Low Priority)**

**Issue**: No unique constraint preventing multiple ongoing trips per user

**Current Protection**: Business logic in `validateTripStatus()` prevents creation

**Recommendation**: Consider adding database-level constraint for extra safety:
```prisma
// Note: This would require a partial unique index in PostgreSQL
// Not directly supported by Prisma, would need raw SQL migration
```

**Status**: ⚠️ **ACCEPTABLE** - Business logic provides sufficient protection, database constraint would be defensive

---

#### **3. GET /trips/status Endpoint Consistency (Low Priority)**

**Issue**: `findFirst` without `orderBy` could return different trips if multiple exist

**Current Protection**: Business logic prevents multiple ongoing trips

**Recommendation**: Add explicit ordering for consistency:
```typescript
const trip = await prisma.trip.findFirst({
  where: { userId, status: "ONGOING" },
  orderBy: { createdAt: 'desc' }, // Most recent if multiple exist
  // ...
});
```

**Status**: ⚠️ **ACCEPTABLE** - Defensive improvement, but not critical

---

### **✅ Final Assessment**

**Overall Security Status**: ✅ **SECURE**

**Race Conditions**: ✅ **NONE IDENTIFIED**
- All backend operations are read-only or already protected
- Frontend state management has minor improvement opportunity (non-critical)

**Transaction Violations**: ✅ **NONE IDENTIFIED**
- No new write operations introduced
- Existing write operations already protected

**Data Integrity**: ✅ **MAINTAINED**
- Username logic secured in PR #34
- Trip status queries are read-only
- Business logic prevents data inconsistencies

**Recommendations Priority**:
1. **Low**: Add concurrency guard to `TripProvider.loadCurrentTrip()` (UI improvement)
2. **Low**: Add `orderBy` to `/trips/status` endpoint (defensive improvement)
3. **Very Low**: Consider database constraint for ongoing trips (defensive, not critical)

**PR #35 Merge Readiness**: ✅ **READY TO MERGE**

**Status**: PR #35 is secure and ready for merge. All identified improvements are low-priority UI/defensive enhancements that don't block merge.

---

## 🛡️ **ERROR HANDLING & VALIDATION REVIEW**

**Review Date**: After Username/Password Login Implementation  
**Scope**: Comprehensive review of error handling and validation across backend (Node.js/TypeScript) and frontend (Flutter)

---

### **📊 EXECUTIVE SUMMARY**

**Overall Status**: ✅ **GOOD** with some areas for improvement

**Backend Error Handling**: ✅ **85% Complete**
- ✅ Custom error classes with proper HTTP status codes
- ✅ Global error middleware with logging
- ✅ Input sanitization for XSS prevention
- ✅ Comprehensive Zod validation schemas
- ⚠️ Some endpoints lack consistent error handling
- ⚠️ SQL injection validation exists but not consistently applied

**Frontend Error Handling**: ✅ **75% Complete**
- ✅ Exception hierarchy implemented
- ✅ Basic retry mechanism exists
- ✅ Connectivity monitoring implemented
- ✅ User-friendly error messages
- ⚠️ No global error boundary (Flutter ErrorWidget)
- ⚠️ Retry mechanism not using exponential backoff consistently
- ⚠️ Error logging to crash reporting service not implemented

---

### **✅ BACKEND ERROR HANDLING - STRENGTHS**

#### 1. **Custom Error Classes** - ✅ **EXCELLENT**

**File**: `src/lib/errors.ts`

**Status**: ✅ **WELL IMPLEMENTED**

**Implementation**:
- Structured error hierarchy with `AppError` base class
- Proper HTTP status codes (400, 401, 403, 404, 409, 429, 500, 503)
- `isOperational` flag to distinguish operational vs programming errors
- Error classes: `ValidationError`, `AuthenticationError`, `AuthorizationError`, `NotFoundError`, `ConflictError`, `RateLimitError`, `DatabaseError`, `ExternalServiceError`

**Coverage**: ✅ Complete error class hierarchy

**Recommendation**: ✅ No changes needed

---

#### 2. **Global Error Middleware** - ✅ **GOOD**

**File**: `src/lib/middleware.ts` (`handleApiError` function)

**Status**: ✅ **IMPLEMENTED**

**Implementation**:
- Centralized error handling via `handleApiError()`
- Converts unknown errors to `AppError`
- Logs non-operational errors
- Returns consistent JSON error response format
- Includes stack trace in development mode only

**Usage**: Used in most API endpoints via try-catch blocks

**Issues Found**:
- ⚠️ **INCONSISTENT USAGE**: Some endpoints use `handleApiError()`, others return error responses directly
- ⚠️ **MISSING LOGGING**: Not all errors are logged with context (request ID, user ID, etc.)
- ⚠️ **NO ERROR MONITORING**: No integration with error monitoring service (Sentry, DataDog, etc.)

**Recommendation**:
```typescript
// Enhanced error handling with monitoring
export function handleApiError(error: unknown, context?: {
  requestId?: string;
  userId?: string;
  endpoint?: string;
}): NextResponse {
  const appError = error instanceof AppError
    ? error
    : new AppError("Internal server error", 500);

  // Enhanced logging with context
  console.error(`[${context?.endpoint || 'unknown'}] Error:`, {
    message: appError.message,
    statusCode: appError.statusCode,
    isOperational: appError.isOperational,
    requestId: context?.requestId,
    userId: context?.userId,
    stack: appError.stack,
  });

  // Send to monitoring service (Sentry, etc.)
  if (!appError.isOperational) {
    // Sentry.captureException(appError, { extra: context });
  }

  return NextResponse.json(
    {
      success: false,
      error: appError.message,
      ...(process.env.NODE_ENV === "development" && { stack: appError.stack }),
    },
    { status: appError.statusCode }
  );
}
```

---

#### 3. **Input Sanitization** - ✅ **GOOD**

**File**: `src/lib/security.ts`

**Status**: ✅ **IMPLEMENTED**

**Implementation**:
- `sanitizeInput()` - Removes HTML tags, javascript: protocol, event handlers
- `escapeHtml()` - HTML entity encoding for XSS prevention
- `validateSqlInput()` - SQL injection pattern detection (additional layer beyond Prisma)

**Usage**: Used in some endpoints (e.g., `src/app/api/places/resolve/route.ts`)

**Issues Found**:
- ⚠️ **INCONSISTENT APPLICATION**: Not all endpoints sanitize user input
- ⚠️ **SQL INJECTION VALIDATION NOT USED**: `validateSqlInput()` exists but not called anywhere
- ⚠️ **PRISMA PROTECTION**: Prisma provides SQL injection protection, but additional validation layer not consistently applied

**Recommendation**:
- Apply `sanitizeInput()` to all text inputs in API endpoints
- Consider using `validateSqlInput()` for user-generated search queries
- Document that Prisma provides primary SQL injection protection

---

#### 4. **Enhanced Validation (Zod Schemas)** - ✅ **EXCELLENT**

**File**: `src/lib/validation.ts`

**Status**: ✅ **WELL IMPLEMENTED**

**Implementation**:
- Comprehensive Zod schemas for all major operations
- Security rules: password strength, username format, email validation
- Unicode normalization for usernames (Cyrillic/Greek lookalikes)
- Input transformation (trim, lowercase, etc.)
- Length limits and format validation

**Schemas Available**:
- `signupSchema` - Email, password, name, username validation
- `loginSchema` - Email/username and password validation
- `updateProfileSchema` - Profile update validation
- `createTripSchema` - Trip creation with date validation
- `createThreadEntrySchema` - Thread entry validation
- `createCommentSchema` - Comment validation
- And more...

**Issues Found**:
- ⚠️ **INCONSISTENT USAGE**: Some endpoints validate manually instead of using schemas
- ⚠️ **DEBUG LOGGING IN PRODUCTION**: Some schemas contain `console.log` debug statements (e.g., `createTripSchema`)

**Recommendation**:
```typescript
// Remove debug logging from production schemas
export const createTripSchema = z.object({
  description: z
    .union([...])
    .optional()
    .transform((val) => {
      // Remove console.log in production
      if (process.env.NODE_ENV === 'development') {
        console.log(`[DEBUG] description validation - received: ${val}`);
      }
      return val;
    }),
});
```

---

#### 5. **Transaction Safety** - ✅ **GOOD** (See Race Condition Analysis)

**Status**: ✅ **MOSTLY SECURE**

**Implementation**: Most critical operations wrapped in `prisma.$transaction()`

**Coverage**: See Race Condition Analysis section for detailed transaction coverage

**Remaining Issues**: 
- Final post generation (end trip) - transaction needed
- Media quota tracking - transaction needed
- Cache stampede - mutex needed

---

### **⚠️ BACKEND ERROR HANDLING - ISSUES FOUND**

#### **Issue 1: Inconsistent Error Handling Across Endpoints**

**Severity**: **MEDIUM**

**Description**: Some endpoints use `handleApiError()`, others return error responses directly, and some use `sanitizeErrorForClient()`.

**Examples**:
- `src/app/api/auth/login/route.ts` - Uses `sanitizeErrorForClient()` ✅
- `src/app/api/auth/signup/route.ts` - Uses direct error responses ⚠️
- `src/app/api/users/me/route.ts` - Uses direct error responses ⚠️

**Impact**: Inconsistent error response format, harder to maintain

**Recommendation**: Standardize on `handleApiError()` or create wrapper that includes `sanitizeErrorForClient()`

---

#### **Issue 2: Missing Error Context in Logging**

**Severity**: **LOW-MEDIUM**

**Description**: Error logs don't include request context (request ID, user ID, endpoint, etc.)

**Impact**: Harder to debug production issues

**Recommendation**: Add request context to all error logs

---

#### **Issue 3: No Error Monitoring Integration**

**Severity**: **MEDIUM**

**Description**: No integration with error monitoring service (Sentry, DataDog, etc.)

**Impact**: Production errors not tracked or alerted

**Recommendation**: Integrate error monitoring service for production

---

#### **Issue 4: SQL Injection Validation Not Used**

**Severity**: **LOW** (Prisma provides protection)

**Description**: `validateSqlInput()` function exists but is never called

**Impact**: Redundant code, but Prisma provides primary protection

**Recommendation**: Either use it for user-generated search queries or remove if not needed

---

#### **Issue 5: Debug Logging in Production Schemas**

**Severity**: **LOW**

**Description**: Some Zod schemas contain `console.log` statements that run in production

**Files**: `src/lib/validation.ts` (lines 243-247, 259-265, etc.)

**Impact**: Unnecessary logging, potential performance impact

**Recommendation**: Remove or guard with `NODE_ENV` check

---

### **✅ FRONTEND ERROR HANDLING - STRENGTHS**

#### 1. **Exception Hierarchy** - ✅ **EXCELLENT**

**File**: `mobile/lib/utils/error_handler.dart`

**Status**: ✅ **WELL IMPLEMENTED**

**Implementation**:
- Base `AppException` class with message, code, and statusCode
- Specialized exceptions: `NetworkException`, `ValidationException`, `AuthenticationException`, `ServerException`
- Error codes for categorization

**Coverage**: ✅ Complete exception hierarchy

**Recommendation**: ✅ No changes needed

---

#### 2. **Error Handler Utility** - ✅ **GOOD**

**File**: `mobile/lib/utils/error_handler.dart` (`ErrorHandler` class)

**Status**: ✅ **IMPLEMENTED**

**Implementation**:
- `handleError()` - Converts DioException to AppException
- `_handleDioError()` - Handles network errors (timeout, connection error, etc.)
- `_handleResponseError()` - Handles HTTP response errors
- `_isTechnicalError()` - Detects technical error messages
- `_getUserFriendlyMessage()` - Converts technical errors to user-friendly messages
- `logError()` - Logs errors (currently only debug mode)

**Issues Found**:
- ⚠️ **CRASH REPORTING NOT IMPLEMENTED**: Commented out Firebase Crashlytics integration
- ⚠️ **NO ERROR CONTEXT**: Logging doesn't include user context, screen context, etc.

**Recommendation**:
```dart
static void logError(
  dynamic error, {
  String? context,
  Map<String, dynamic>? additionalData,
  StackTrace? stackTrace,
}) {
  // Always log in debug mode
  if (kDebugMode) {
    debugPrint('Error in $context: $error');
    if (additionalData != null) {
      debugPrint('Additional data: $additionalData');
    }
    if (stackTrace != null) {
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // In production, send to crash reporting service
  // TODO: Implement Firebase Crashlytics or Sentry
  // FirebaseCrashlytics.instance.recordError(
  //   error,
  //   stackTrace,
  //   reason: context,
  //   information: additionalData?.entries.map((e) => 
  //     Parameter(key: e.key, value: e.value.toString())
  //   ).toList(),
  // );
}
```

---

#### 3. **Retry Mechanism** - ⚠️ **PARTIAL**

**File**: `mobile/lib/utils/error_handler.dart` (`RetryHandler` class)

**Status**: ⚠️ **IMPLEMENTED BUT NOT USED**

**Implementation**:
- `RetryHandler.retry()` - Implements retry with exponential backoff
- Max retries: 3 (configurable)
- Exponential backoff: `delay * attempts`
- Conditional retry via `retryIf` callback

**Issues Found**:
- ⚠️ **NOT USED**: `RetryHandler` is defined but not used anywhere in the codebase
- ⚠️ **TOKEN REFRESH RETRY**: API service has custom retry logic for 401 errors, but doesn't use `RetryHandler`
- ⚠️ **NO EXPONENTIAL BACKOFF IN API SERVICE**: Token refresh retry doesn't use exponential backoff

**Current Usage**: Manual retry buttons in UI screens

**Recommendation**: 
- Use `RetryHandler` for network requests in API service
- Apply exponential backoff to token refresh retry
- Consider automatic retry for transient network errors

---

#### 4. **Connectivity Monitoring** - ✅ **EXCELLENT**

**File**: `mobile/lib/services/connectivity_service.dart`

**Status**: ✅ **WELL IMPLEMENTED**

**Implementation**:
- `ConnectivityService` - Singleton service using `connectivity_plus` package
- Real-time connectivity status via `StreamSubscription`
- Properties: `isConnected`, `isWifi`, `isMobile`, `connectionStatus`
- `ConnectivityToastHandler` widget - Shows toast when connectivity changes

**Usage**: Integrated in `main.dart`, used throughout app

**Coverage**: ✅ Complete connectivity monitoring

**Recommendation**: ✅ No changes needed

---

#### 5. **User-Friendly Error Messages** - ✅ **GOOD**

**File**: `mobile/lib/utils/error_handler.dart`

**Status**: ✅ **IMPLEMENTED**

**Implementation**:
- `_isTechnicalError()` - Detects technical error messages from backend
- `_getUserFriendlyMessage()` - Converts technical errors to user-friendly messages
- Error messages shown in UI via `AuthProvider.error` and other providers

**Coverage**: ✅ Most errors have user-friendly messages

**Recommendation**: ✅ No changes needed

---

### **⚠️ FRONTEND ERROR HANDLING - ISSUES FOUND**

#### **Issue 1: No Global Error Boundary**

**Severity**: **MEDIUM**

**Description**: Flutter app doesn't have a global `ErrorWidget.builder` to catch unhandled errors

**Impact**: Unhandled errors can crash the app without graceful fallback

**Current State**: Errors are caught in individual try-catch blocks, but no global error boundary

**Recommendation**:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set up global error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // Log to crash reporting service
    ErrorHandler.logError(
      details.exception,
      context: 'Flutter Framework Error',
      additionalData: {
        'library': details.library,
        'context': details.context?.toString(),
      },
      stackTrace: details.stack,
    );
  };

  // Handle errors outside Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorHandler.logError(
      error,
      context: 'Platform Error',
      stackTrace: stack,
    );
    return true;
  };

  // Custom error widget
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Something went wrong'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                // Restart app or navigate to home
              },
              child: const Text('Restart App'),
            ),
          ],
        ),
      ),
    );
  };

  // ... rest of main()
}
```

---

#### **Issue 2: Retry Mechanism Not Used**

**Severity**: **MEDIUM**

**Description**: `RetryHandler` class exists but is never used. API service has custom retry logic that doesn't use exponential backoff.

**Impact**: Network requests don't automatically retry on transient errors

**Recommendation**: 
- Use `RetryHandler` in API service for transient network errors
- Apply exponential backoff to token refresh retry
- Consider automatic retry for 5xx server errors

---

#### **Issue 3: Crash Reporting Not Implemented**

**Severity**: **MEDIUM**

**Description**: `ErrorHandler.logError()` has commented-out Firebase Crashlytics integration

**Impact**: Production errors not tracked

**Recommendation**: Implement crash reporting service (Firebase Crashlytics, Sentry, etc.)

---

#### **Issue 4: No Error Context in Logging**

**Severity**: **LOW**

**Description**: Error logging doesn't include user context, screen context, or request details

**Impact**: Harder to debug production issues

**Recommendation**: Add context to error logs (user ID, current screen, request details, etc.)

---

#### **Issue 5: Manual Retry Buttons Instead of Automatic Retry**

**Severity**: **LOW**

**Description**: Many screens have "Retry" buttons for manual retry instead of automatic retry

**Impact**: Poor user experience - users must manually retry failed operations

**Recommendation**: Implement automatic retry for transient errors with exponential backoff

---

### **📋 RECOMMENDATIONS SUMMARY**

#### **Backend (High Priority)**

1. **Standardize Error Handling** - Use `handleApiError()` consistently across all endpoints
2. **Add Error Monitoring** - Integrate Sentry or similar service
3. **Remove Debug Logging** - Remove or guard `console.log` statements in production schemas
4. **Add Request Context** - Include request ID, user ID, endpoint in error logs

#### **Backend (Medium Priority)**

5. **Apply Input Sanitization** - Use `sanitizeInput()` consistently across all endpoints
6. **Use SQL Validation** - Apply `validateSqlInput()` for user-generated search queries or remove if not needed

#### **Frontend (High Priority)**

7. **Add Global Error Boundary** - Implement `ErrorWidget.builder` and `FlutterError.onError`
8. **Implement Crash Reporting** - Set up Firebase Crashlytics or Sentry
9. **Use Retry Handler** - Apply `RetryHandler` to API service for automatic retries

#### **Frontend (Medium Priority)**

10. **Add Error Context** - Include user context, screen context in error logs
11. **Automatic Retry** - Implement automatic retry for transient errors

---

### **📊 ERROR HANDLING COVERAGE MATRIX**

| Component | Status | Coverage | Priority Issues |
|-----------|--------|----------|----------------|
| Backend Error Classes | ✅ Excellent | 100% | None |
| Backend Error Middleware | ✅ Good | 80% | Inconsistent usage |
| Backend Input Sanitization | ✅ Good | 60% | Not consistently applied |
| Backend Validation (Zod) | ✅ Excellent | 95% | Debug logging in production |
| Backend Transactions | ✅ Good | 85% | See Race Condition Analysis |
| Frontend Exception Hierarchy | ✅ Excellent | 100% | None |
| Frontend Error Handler | ✅ Good | 90% | Crash reporting not implemented |
| Frontend Retry Mechanism | ⚠️ Partial | 30% | Not used, no exponential backoff |
| Frontend Connectivity | ✅ Excellent | 100% | None |
| Frontend Error Messages | ✅ Good | 90% | None |
| Frontend Error Boundary | ❌ Missing | 0% | No global error boundary |

**Overall Backend Score**: ✅ **85%**  
**Overall Frontend Score**: ✅ **75%**  
**Combined Score**: ✅ **80%**

---

### **🛠️ IMPLEMENTATION PRIORITY**

**Phase 1 (Critical - Week 1)**:
1. Add global error boundary in Flutter app
2. Standardize backend error handling
3. Remove debug logging from production schemas

**Phase 2 (Important - Week 2)**:
4. Implement crash reporting (Firebase Crashlytics/Sentry)
5. Use RetryHandler in API service
6. Add error context to logs

**Phase 3 (Enhancement - Week 3)**:
7. Apply input sanitization consistently
8. Add automatic retry for transient errors
9. Integrate error monitoring service

---

## 🏗️ **SCALABLE ARCHITECTURE REVIEW**

**Review Date**: After Username/Password Login Implementation  
**Scope**: Comprehensive review of performance monitoring, rate limiting & caching, and modular design

---

### **📊 EXECUTIVE SUMMARY**

**Overall Status**: ✅ **GOOD** with strong foundation, some areas need enhancement

**Performance Monitoring**: ✅ **75% Complete**
- ✅ Operation timing implemented
- ✅ System metrics available
- ✅ Health checks endpoint exists
- ⚠️ Memory leak detection not implemented
- ⚠️ Database query timing not tracked separately

**Rate Limiting & Caching**: ✅ **90% Complete**
- ✅ Comprehensive rate limiting with per-user and per-IP
- ✅ Multi-level caching (memory + Redis)
- ✅ Performance metrics tracking
- ⚠️ Cache stampede protection needed (see Race Condition Analysis)
- ⚠️ Some database queries could benefit from additional indexes

**Modular Design**: ✅ **85% Complete**
- ✅ Service layer separation
- ✅ Middleware composition
- ✅ Provider pattern in Flutter
- ⚠️ Dependency injection could be more explicit
- ⚠️ Some services have tight coupling

---

### **✅ PERFORMANCE MONITORING - STRENGTHS**

#### 1. **Operation Timing** - ✅ **GOOD**

**File**: `src/lib/monitoring.ts` (`PerformanceMonitor` class)

**Status**: ✅ **IMPLEMENTED**

**Implementation**:
- Singleton `PerformanceMonitor` class
- `startTimer()` method returns stop function
- Tracks avg, min, max, count for each operation
- Keeps last 100 measurements per operation
- Logs warnings for slow operations (>1 second)

**Usage**: Used in several endpoints:
- `src/app/api/trips/route.ts` - `create_trip` timing
- `src/app/api/users/[id]/stats/route.ts` - `get_user_stats` timing
- `src/app/api/discover/trips/route.ts` - `get_discover_trips` timing

**Issues Found**:
- ⚠️ **INCONSISTENT USAGE**: Not all endpoints use performance monitoring
- ⚠️ **NO DATABASE QUERY TIMING**: Database queries not tracked separately
- ⚠️ **MEMORY-BASED ONLY**: Metrics stored in memory, lost on restart
- ⚠️ **NO PERSISTENCE**: No historical metrics storage

**Recommendation**:
```typescript
// Enhanced performance monitoring with persistence
export class PerformanceMonitor {
  // Add database query timing
  startDbQueryTimer(query: string): () => void {
    return this.startTimer(`db_query:${query}`);
  }

  // Add persistence layer
  async persistMetrics(): Promise<void> {
    // Store metrics to database or external service
    // Consider using time-series database (InfluxDB, TimescaleDB)
  }

  // Add alerting for slow operations
  recordMetric(operation: string, duration: number): void {
    // ... existing code ...
    
    // Alert if operation consistently slow
    if (duration > 2000 && operationMetrics.length > 10) {
      const avg = operationMetrics.reduce((a, b) => a + b, 0) / operationMetrics.length;
      if (avg > 2000) {
        // Send alert to monitoring service
        console.error(`ALERT: ${operation} consistently slow (avg: ${avg}ms)`);
      }
    }
  }
}
```

---

#### 2. **Memory Usage Monitoring** - ⚠️ **PARTIAL**

**File**: `src/lib/monitoring.ts` (`getSystemMetrics` function)

**Status**: ⚠️ **BASIC IMPLEMENTATION**

**Implementation**:
- `getSystemMetrics()` returns `process.memoryUsage()`
- Includes heap used, heap total, external, rss
- Available via `/api/health` endpoint

**Issues Found**:
- ⚠️ **NO MEMORY LEAK DETECTION**: No tracking of memory growth over time
- ⚠️ **NO ALERTS**: No alerts when memory usage is high
- ⚠️ **NO HISTORICAL DATA**: Memory metrics not persisted

**Recommendation**:
```typescript
export class MemoryMonitor {
  private memoryHistory: Array<{ timestamp: number; usage: NodeJS.MemoryUsage }> = [];
  
  recordMemoryUsage(): void {
    this.memoryHistory.push({
      timestamp: Date.now(),
      usage: process.memoryUsage(),
    });
    
    // Keep last 1000 measurements
    if (this.memoryHistory.length > 1000) {
      this.memoryHistory.shift();
    }
    
    // Detect memory leaks (consistent growth over time)
    if (this.memoryHistory.length > 100) {
      const recent = this.memoryHistory.slice(-100);
      const older = this.memoryHistory.slice(-200, -100);
      const recentAvg = recent.reduce((sum, m) => sum + m.usage.heapUsed, 0) / recent.length;
      const olderAvg = older.reduce((sum, m) => sum + m.usage.heapUsed, 0) / older.length;
      
      if (recentAvg > olderAvg * 1.2) {
        console.warn(`Potential memory leak detected: ${((recentAvg / olderAvg - 1) * 100).toFixed(2)}% growth`);
      }
    }
    
    // Alert on high memory usage
    const heapUsedMB = process.memoryUsage().heapUsed / 1024 / 1024;
    if (heapUsedMB > 500) { // 500MB threshold
      console.warn(`High memory usage: ${heapUsedMB.toFixed(2)}MB`);
    }
  }
}
```

---

#### 3. **Health Checks** - ✅ **EXCELLENT**

**File**: `src/app/api/health/route.ts`

**Status**: ✅ **WELL IMPLEMENTED**

**Implementation**:
- Comprehensive health check endpoint
- Database health check with latency
- External services health check (configurable)
- System metrics (memory, uptime)
- Performance metrics from `PerformanceMonitor`
- Error statistics from `ErrorTracker`
- Returns status: `healthy`, `degraded`, or `unhealthy`
- Proper HTTP status codes (200 for healthy, 503 for unhealthy)

**Coverage**: ✅ Complete health monitoring

**Issues Found**:
- ⚠️ **EXTERNAL SERVICES NOT CONFIGURED**: `checkExternalServices()` has empty services object
- ⚠️ **NO ALERTING**: Health check doesn't trigger alerts

**Recommendation**:
```typescript
// Configure external services
const services: Record<string, string> = {
  'cloudinary': 'https://api.cloudinary.com/v1_1/health',
  // Add other external services
};

// Add alerting integration
if (health.status !== 'healthy') {
  // Send alert to monitoring service (PagerDuty, etc.)
  // await sendAlert({ status: health.status, details: health });
}
```

---

### **✅ RATE LIMITING & CACHING - STRENGTHS**

#### 1. **API Rate Limiting** - ✅ **EXCELLENT**

**File**: `src/lib/rateLimit.ts`

**Status**: ✅ **WELL IMPLEMENTED**

**Implementation**:
- Comprehensive rate limiting with presets for all endpoints
- Per-user and per-IP rate limiting
- Fixed window algorithm (default)
- Sliding window algorithm (available for comments)
- Redis-backed with memory fallback
- Configurable limits per endpoint type
- Rate limit headers in responses (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`)
- Security event logging for rate limit hits

**Presets Available**:
- Engagement actions: comment (15/15min), share (100/24h), like (200/1h)
- Auth endpoints: login (100/15min), signup (100/1h), forgot (2/1h), reset (2/1h)
- General API: 100/minute
- Search: 30/minute
- Places: 100/minute

**Coverage**: ✅ All major endpoints have rate limiting

**Issues Found**:
- ⚠️ **SLIDING WINDOW DISABLED**: Comment endpoint has sliding window but it's disabled (line 524-529)
- ⚠️ **NO RATE LIMIT METRICS**: No tracking of rate limit effectiveness

**Recommendation**: 
- Enable sliding window for comment endpoint when ready
- Add metrics tracking for rate limit hits/misses

---

#### 2. **Request Throttling** - ✅ **EXCELLENT**

**File**: `src/lib/rateLimit.ts`

**Status**: ✅ **WELL IMPLEMENTED**

**Implementation**:
- Per-user throttling (when authenticated)
- Per-IP throttling (when not authenticated)
- Identifier extraction from request headers
- Fallback to memory cache if Redis unavailable
- Graceful degradation (allows request if rate limiting fails)

**Coverage**: ✅ Comprehensive throttling

**Recommendation**: ✅ No changes needed

---

#### 3. **Performance Metrics** - ✅ **GOOD**

**File**: `src/lib/monitoring.ts`, `src/lib/cache.ts`

**Status**: ✅ **IMPLEMENTED**

**Implementation**:
- `PerformanceMonitor` tracks operation timing
- Cache metrics available via `getCacheMetrics()`
- Cache hit/miss rates tracked
- Memory and Redis cache stats

**Issues Found**:
- ⚠️ **NO METRICS EXPORT**: Metrics not exported to monitoring service
- ⚠️ **NO DASHBOARD**: No visualization of metrics

**Recommendation**: Integrate with monitoring service (Prometheus, DataDog, etc.)

---

#### 4. **Caching Implementation** - ✅ **EXCELLENT**

**File**: `src/lib/cache.ts`, `src/lib/redis.ts`

**Status**: ✅ **WELL IMPLEMENTED**

**Implementation**:
- Multi-level caching: Memory (LRU) + Redis
- `getOrSet()` function for cache-aside pattern
- LRU cache with TTL support
- Redis integration with Upstash
- Memory cache fallback if Redis unavailable
- Cache metrics tracking

**Usage**: Used for place resolution, share tokens, etc.

**Issues Found**:
- ⚠️ **CACHE STAMPEDE**: `getOrSet()` has race condition (see Race Condition Analysis)
- ⚠️ **NO CACHE WARMING**: No proactive cache warming for frequently accessed data

**Recommendation**: 
- Add mutex/lock to `getOrSet()` to prevent cache stampede
- Consider cache warming for hot data

---

#### 5. **Database Optimization** - ✅ **GOOD**

**File**: `prisma/schema.prisma`

**Status**: ✅ **WELL INDEXED**

**Indexes Defined**:
- `PasswordReset`: `@@index([userId, expiresAt])`
- `SecurityEvent`: `@@index([eventType, createdAt])`, `@@index([userId, createdAt])`, `@@index([entityType, entityId])`
- `JWTRefreshToken`: `@@index([userId])`, `@@index([expiresAt])`
- `Place`: `@@index([lat, lng])` (spatial), `@@index([externalId])`
- `PlaceOnTrip`: `@@index([tripId, visitedAt])`
- `Like`: `@@index([entityType, entityId, createdAt])`, `@@index([userId])`
- `Comment`: `@@index([entityType, entityId, createdAt])`, `@@index([parentCommentId])`, `@@index([userId])`
- `Share`: `@@index([userId, createdAt])`, `@@index([entityType, entityId])`

**Unique Constraints**:
- `User`: `email`, `username`
- `Follow`: `[followerId, followeeId]`
- `FollowRequest`: `[followerId, followeeId]`
- `TripJoinRequest`: `[tripId, receiverId]`
- `TripParticipant`: `[tripId, userId]`
- And more...

**Issues Found**:
- ⚠️ **MISSING INDEXES**: Some common query patterns may not be indexed:
  - `Trip`: No index on `[userId, status]` for user's trips by status
  - `Trip`: No index on `[status, endDate]` for discover queries
  - `TripThreadEntry`: No index on `[tripId, createdAt]` for chronological ordering
  - `Media`: No index on `[uploadedById, createdAt]` for user's media
  - `TripParticipant`: No index on `[userId]` for user's trips

**Recommendation**:
```prisma
model Trip {
  // ... existing fields ...
  
  @@index([userId, status]) // For user's trips by status
  @@index([status, endDate]) // For discover queries
  @@index([status, createdAt]) // For feed ordering
  @@map("trips")
}

model TripThreadEntry {
  // ... existing fields ...
  
  @@index([tripId, createdAt]) // For chronological ordering
  @@map("trip_thread_entries")
}

model Media {
  // ... existing fields ...
  
  @@index([uploadedById, createdAt]) // For user's media
  @@map("media")
}

model TripParticipant {
  // ... existing fields ...
  
  @@index([userId]) // For user's trips
  @@map("trip_participants")
}
```

---

### **✅ MODULAR DESIGN - STRENGTHS**

#### 1. **Service Layer Separation** - ✅ **EXCELLENT**

**Directory**: `src/lib/services/`

**Status**: ✅ **WELL ORGANIZED**

**Services Available**:
- `comment.ts` - Comment business logic
- `email.ts` - Email sending
- `engagement-utils.ts` - Engagement utilities
- `googleAuth.ts` - Google OAuth
- `like.ts` - Like operations
- `passwordReset.ts` - Password reset flow
- `securityEvent.ts` - Security event logging
- `share.ts` - Share operations
- `token.ts` - Token management
- `tripFinalizer.ts` - Final post generation

**Pattern**: Each service handles specific domain logic

**Issues Found**:
- ⚠️ **NO EXPLICIT DI**: Services are imported directly, not injected
- ⚠️ **SOME TIGHT COUPLING**: Some services depend on Prisma directly

**Recommendation**: Consider dependency injection container for better testability

---

#### 2. **Middleware Composition** - ✅ **EXCELLENT**

**File**: `src/lib/middleware.ts`

**Status**: ✅ **WELL IMPLEMENTED**

**Middleware Available**:
- `withAuth()` - Authentication
- `withRateLimit()` - Rate limiting
- `withLogging()` - Request logging
- `withValidation()` - Input validation
- `withCors()` - CORS handling
- `withSecurityHeaders()` - Security headers

**Pattern**: Composable middleware functions

**Usage Example**:
```typescript
export async function POST(request: NextRequest) {
  return await withCors(async (req) => {
    const loggedHandler = withLogging(async (loggedReq) => {
      return await withRateLimit(loggedReq, "auth_login", async (rateLimitedReq) => {
        // Handler code
      });
    });
    return await loggedHandler(req);
  })(request);
}
```

**Coverage**: ✅ All middleware well-designed and reusable

**Recommendation**: ✅ No changes needed

---

#### 3. **Provider Pattern (Flutter)** - ✅ **EXCELLENT**

**Directory**: `mobile/lib/providers/`

**Status**: ✅ **WELL IMPLEMENTED**

**Providers Available**:
- `AuthProvider` - Authentication state
- `UserProvider` - User data and caching
- `TripProvider` - Trip management
- `FeedProvider` - Home feed
- `CommentProvider` - Comments
- `EngagementProvider` - Likes, shares
- `FinalPostProvider` - Final posts
- `PlaceProvider` - Places
- `ShareProvider` - Share operations

**Pattern**: ChangeNotifier-based providers with separation of concerns

**State Management**: Uses Provider package with proper dependency injection

**Issues Found**:
- ⚠️ **SOME PROVIDERS LARGE**: Some providers (e.g., `TripProvider`) are large and could be split
- ⚠️ **CACHE MANAGEMENT**: Cache invalidation logic scattered across providers

**Recommendation**: 
- Consider splitting large providers into smaller, focused providers
- Centralize cache invalidation logic

---

#### 4. **Service Layer (Flutter)** - ✅ **EXCELLENT**

**Directory**: `mobile/lib/services/`

**Status**: ✅ **WELL ORGANIZED**

**Services Available**:
- `ApiService` - HTTP client with interceptors
- `StorageService` - Local storage
- `ConnectivityService` - Network monitoring
- `MediaService` - Media uploads
- `TripService` - Trip operations
- `CommentService` - Comment operations
- `LikeService` - Like operations
- `ShareService` - Share operations
- `PlacesService` - Place operations
- `GoogleSignInService` - OAuth
- `DeepLinkService` - Deep linking
- `TokenRefreshManager` - Token refresh

**Pattern**: Services handle API communication, providers handle state

**Coverage**: ✅ Complete service layer separation

**Recommendation**: ✅ No changes needed

---

### **⚠️ SCALABLE ARCHITECTURE - ISSUES FOUND**

#### **Issue 1: Performance Monitoring Not Used Consistently**

**Severity**: **MEDIUM**

**Description**: `PerformanceMonitor` exists but not all endpoints use it

**Impact**: Cannot track performance of all operations

**Recommendation**: Add performance monitoring to all critical endpoints

---

#### **Issue 2: Memory Leak Detection Missing**

**Severity**: **MEDIUM**

**Description**: No tracking of memory growth over time

**Impact**: Memory leaks may go undetected

**Recommendation**: Implement memory monitoring with leak detection

---

#### **Issue 3: Cache Stampede Protection Missing**

**Severity**: **MEDIUM** (See Race Condition Analysis)

**Description**: `getOrSet()` has race condition allowing cache stampede

**Impact**: Multiple requests can trigger expensive operations simultaneously

**Recommendation**: Add mutex/lock to `getOrSet()`

---

#### **Issue 4: Missing Database Indexes**

**Severity**: **LOW-MEDIUM**

**Description**: Some common query patterns not indexed

**Impact**: Slower queries as data grows

**Recommendation**: Add indexes for common query patterns (see recommendations above)

---

#### **Issue 5: External Services Health Check Not Configured**

**Severity**: **LOW**

**Description**: `checkExternalServices()` has empty services object

**Impact**: Cannot monitor external service health

**Recommendation**: Configure external service URLs

---

#### **Issue 6: No Metrics Export**

**Severity**: **LOW-MEDIUM**

**Description**: Performance metrics not exported to monitoring service

**Impact**: Cannot visualize or alert on metrics

**Recommendation**: Integrate with monitoring service (Prometheus, DataDog, etc.)

---

### **📋 RECOMMENDATIONS SUMMARY**

#### **High Priority**

1. **Add Missing Database Indexes** - Add indexes for common query patterns
2. **Fix Cache Stampede** - Add mutex to `getOrSet()` (see Race Condition Analysis)
3. **Consistent Performance Monitoring** - Add monitoring to all critical endpoints

#### **Medium Priority**

4. **Memory Leak Detection** - Implement memory monitoring
5. **Metrics Export** - Integrate with monitoring service
6. **Configure External Services** - Add external service URLs to health check

#### **Low Priority**

7. **Split Large Providers** - Refactor large providers into smaller ones
8. **Centralize Cache Invalidation** - Create cache invalidation service

---

### **📊 SCALABLE ARCHITECTURE COVERAGE MATRIX**

| Component | Status | Coverage | Priority Issues |
|-----------|--------|----------|----------------|
| Performance Monitoring | ✅ Good | 75% | Not used consistently |
| Operation Timing | ✅ Good | 60% | Not all endpoints tracked |
| Memory Monitoring | ⚠️ Basic | 40% | No leak detection |
| Health Checks | ✅ Excellent | 100% | External services not configured |
| Rate Limiting | ✅ Excellent | 95% | Sliding window disabled |
| Request Throttling | ✅ Excellent | 100% | None |
| Caching | ✅ Excellent | 90% | Cache stampede (see Race Condition) |
| Database Indexes | ✅ Good | 85% | Some common patterns missing |
| Service Layer | ✅ Excellent | 100% | No explicit DI |
| Middleware Composition | ✅ Excellent | 100% | None |
| Provider Pattern | ✅ Excellent | 100% | Some providers large |
| Service Layer (Flutter) | ✅ Excellent | 100% | None |

**Overall Performance Monitoring Score**: ✅ **75%**  
**Overall Rate Limiting & Caching Score**: ✅ **90%**  
**Overall Modular Design Score**: ✅ **85%**  
**Combined Scalable Architecture Score**: ✅ **83%**

---

### **🛠️ IMPLEMENTATION PRIORITY (Scalable Architecture)**

**Phase 1 (Critical - Week 1)**:
1. Add missing database indexes for common query patterns
2. Fix cache stampede in `getOrSet()` (see Race Condition Analysis)
3. Add performance monitoring to all critical endpoints

**Phase 2 (Important - Week 2)**:
4. Implement memory leak detection
5. Configure external services in health check
6. Enable sliding window rate limiting for comments

**Phase 3 (Enhancement - Week 3)**:
7. Integrate metrics export to monitoring service
8. Split large providers into smaller, focused providers
9. Add cache warming for hot data

**Phase 1 (Critical - Week 1)**:
1. Add global error boundary in Flutter app
2. Standardize backend error handling
3. Remove debug logging from production schemas

**Phase 2 (Important - Week 2)**:
4. Implement crash reporting (Firebase Crashlytics/Sentry)
5. Use RetryHandler in API service
6. Add error context to logs

**Phase 3 (Enhancement - Week 3)**:
7. Apply input sanitization consistently
8. Add automatic retry for transient errors
9. Integrate error monitoring service

---

## 🚨 PR #35 — NEW RACE CONDITIONS (UX Enhancements)

### 15. **Logout Empty Body Fallback — Silent Revoke All** - ✅ FIXED

**File**: `src/app/api/auth/logout/route.ts` (POST handler)

**Original Issue**: When the request body was malformed or empty, the logout endpoint silently revoked ALL refresh tokens for the user instead of just the current session.

**Fix Applied**: When no `refreshToken` is provided and `logoutAll` isn't explicitly `true`, the server now logs a warning and returns success without revoking any server-side tokens. Client-side token clearing is sufficient for the current device.

```typescript
if (logoutAll === true) {
  await revokeAllRefreshTokens(userId);
} else if (refreshToken && typeof refreshToken === "string") {
  await AuthService.revokeRefreshToken(refreshToken);
} else {
  // Don't revoke all — log warning and return success
  console.warn(`[Logout] No refreshToken provided for user ${userId}, skipping server-side revoke`);
}
```

---

### 16. **Mobile Retry on Non-Idempotent Mutations** - ✅ FIXED

**File**: `mobile/lib/services/api_service.dart` (`_retryRequest` method)

**Original Issue**: The mobile API service retried on 5xx errors and timeouts for ALL request methods including POST/PUT/DELETE. If a POST request committed on the server but failed on the response, the retry would create duplicate data.

**Fix Applied**: Added HTTP method check at the top of the retry predicate — only `GET` and `HEAD` requests are retried. All mutation methods (POST, PUT, DELETE) fail immediately.

```dart
retryIf: (error) {
  if (error is DioException) {
    final method = error.requestOptions.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') {
      return false; // Don't retry mutations
    }
    // ... existing retry logic for GET requests
  }
  return false;
},
```

---

### PR #35 Race Condition Summary

| # | Issue | File | Severity | Status |
|---|-------|------|----------|--------|
| 15 | Logout empty body → revokeAll fallback | `auth/logout/route.ts` | MEDIUM | ✅ FIXED |
| 16 | Mobile retry on POST/PUT/DELETE mutations | `api_service.dart` | HIGH | ✅ FIXED |

**Note**: Additional non-race-condition issues from PR #35 are documented in `documentations/PR35_UX_ENHANCEMENTS_REVIEW.md`.

