# Security and middleware

Authentication, rate limits, CORS, and security headers are wrappers in `src/lib/middleware.ts` and `src/lib/rateLimit.ts`. Next.js `src/middleware.ts` is not the API auth layer. It only checks that reset pages have a plausible `t` and `email` query.

## withAuth

1. Require `Authorization: Bearer <access JWT>`.
2. `AuthService.verifyAccessToken` with `JWT_SECRET`.
3. Load `id`, `email`, `updatedAt`. Missing user is **401**.
4. If `iat` is more than one second older than `updatedAt`, **401**. Credential and profile writes move `updatedAt`, so stolen access tokens stop working without a denylist.
5. Set `request.user = { userId, email }`.

`getOptionalUser` runs the same checks and returns null on failure. Feed-adjacent public reads (place search, public profile) use it so a logged-in viewer gets personalization and an anonymous viewer still gets a response.

`handleApiError` maps `AppError.statusCode` to JSON `{ success: false, error }`. In development the payload can include `stack`. `UnsettledBalanceError` adds `code` and `meta.netMinor`.

## Rate limits

Fixed window, Redis `INCR` plus `PEXPIRE`, memory if Redis is down or the circuit is open. The full table is in [Redis](./09-redis-cache-and-queues.md).

Design choices that matter when you add a route:

- Key by user id on authenticated routes so one NAT does not exhaust a shared IP budget. Key by IP on login, signup, and forgot-password, because there is no user yet and the point is to slow guessing.
- Forgot-password and reset are **2 per hour**. That is the anti-enumeration and anti-mail-bomb control, paired with the generic "if an account exists" response.
- `read_hot` at 240 per minute covers feed, profile, and notifications, which the app polls.
- `write` at 60 per minute covers trip mutations.
- `chat_message` at 30 per minute is separate so a chatty room cannot consume the write budget of trip edits, and the reverse.
- Fail open if the limiter throws. A Redis bug should not take down reads. A misconfigured preset is **500**, because that is a deploy error, not an outage.

A limited request that is over budget can log `SecurityEvent` `RATE_LIMIT_HIT` with identifier, limit, window, and path (`src/lib/rateLimit.ts`). `getAbuseScore(userId, hours = 24)` in `src/lib/security/events.ts` counts `RATE_LIMIT_HIT`, `PROFANITY_DETECTED`, and `ABUSE_DETECTED` for that user. The score is available to moderation. It is not, by itself, a ban.

## Headers and CORS

`withSecurityHeaders` sets:

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`

That `Permissions-Policy` is on API responses. The Flutter app requests camera and location through the OS, not through a browser document served by this header. The web UI is a different origin (nginx). Do not read this header as "the product has no camera".

`src/lib/security.ts` exports a stricter `securityHeaders` object that includes HSTS and a Content-Security-Policy. `withSecurityHeaders` does not apply that object. HSTS and CSP are not on API responses today.

`withCors`:

- `OPTIONS` returns **204**.
- Methods `GET, POST, PUT, DELETE, PATCH, OPTIONS`.
- Allowed request headers `Content-Type, Authorization, X-Requested-With`.
- `Access-Control-Allow-Credentials: true`.
- If the `Origin` is in `ALLOWED_ORIGINS` (CSV, localhost defaults in `config.allowedOrigins`), that origin is echoed. No origin (native app) gets `*`. Preflight `Access-Control-Max-Age` is **86400**.

Signup and login use `withCors`. Several later auth routes do not wrap `withCors` themselves. Native clients do not need CORS. The browser reset page is same-origin with the API when nginx proxies it.

## Input validation

Zod schemas live in `src/lib/validation.ts`. `withValidation` turns a Zod error into **400** with the first issue message. Password policy is shared with `src/lib/password-policy.ts` (8–128, upper, lower, digit). Usernames are normalized and lowercased before the unique check so lookalike characters cannot squat a second account.

`src/lib/utils/sanitize.ts` and `src/lib/security/moderation.ts` cover text cleanup and profanity checks used on comments and thread text. A profanity hit can record `PROFANITY_DETECTED`. Comment reports use `COMMENT_REPORT`. Those are real `SecurityEventType` values.

## Security events

`security_events` columns: `eventType`, optional `userId`, optional `entityType` and `entityId`, `ipAddress`, required `metadata` JSON, `createdAt`. Indexes `(eventType, createdAt)`, `(userId, createdAt)`, `(entityType, entityId)`.

Enum: `COMMENT_REPORT`, `PROFANITY_DETECTED`, `RATE_LIMIT_HIT`, `ABUSE_DETECTED`, `UNAUTHORIZED_ACCESS`.

`recordSecurityEvent` from the password-reset service is called with `PASSWORD_RESET_REQUESTED`, `PASSWORD_RESET_SUCCESS`, and `PASSWORD_CHANGED`. Those are not in the enum. The Prisma create throws, and the `.catch(() => {})` drops it. Password resets are still real (the `password_resets` row and the email exist). They do not show up in `security_events`. If you add audit for password changes, extend the enum in a migration first.

## Upload safety

Documented in full in [Media](./07-media-cloudinary.md). The short version: the API never accepts the file body. It signs a Cloudinary upload, then on confirm checks cloud host, MIME allowlist, filename grammar, 50 MB cap, and the first 512 bytes of magic numbers. Quota is enforced in our database, not by hoping the client told the truth about `bytes`.

## Token storage

Native tokens sit in the platform secure store. The web build stores them in `SharedPreferences`, which is not encrypted. That was a deliberate trade against a WebCrypto bug that blocked login. Treat the Docker web UI as a development surface. Production phone builds keep `flutter_secure_storage`.

Refresh tokens are stored in Postgres in full, unique, and deleted on rotation, logout, password reset, and account delete. There is no refresh-token hash column. A database read exposes live refresh tokens. Access tokens are not stored server-side. They die by expiry or by the `updatedAt` check.

## Account deletion and money

Deletion is refused while any trip net is non-zero, so a user cannot erase an unsettled ledger by deleting the account. The email is rewritten and the password is nulled, which is what makes the old login fail. See [Profiles](./03-profiles-and-privacy.md) and [Expenses](./10-expenses-and-settlements.md).

## Race controls

| Race | Control |
| --- | --- |
| Double like | Unique `(userId, entityType, entityId)` and `P2002` treated as success |
| Double follow | Unique pair, **409** |
| Double place insert | `mutex` lock on external id or spatial key, then unique `externalId` |
| Double refresh | Unique `refreshToken`, `jti`, delete-on-rotate |
| Stale settlement | `FOR UPDATE` on the trip, amount must match a current simplify-debts edge |
| Cache stampede | `SET NX cache-lock:{key}` for 8 seconds |
| Reset token reuse | `SELECT FOR UPDATE`, set `usedAt` before the password update |
| Google link race | Transaction plus `P2002` re-fetch |

`documentations/RACE_CONDITION_ANALYSIS.md` is the earlier write-up of several of these. Where it disagrees with the code, prefer this handbook.
