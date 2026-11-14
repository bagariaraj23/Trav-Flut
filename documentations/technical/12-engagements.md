# Engagements

Likes, comments, and shares attach to an entity, not to a special post table. The entity is `TRIP_FINAL_POST`, `TRIP_THREAD_ENTRY`, or, for likes of a comment, `COMMENT`.

Primary files:

- `src/lib/services/like.ts`
- `src/lib/services/comment.ts`
- `src/lib/services/share.ts`
- `src/lib/services/engagement-utils.ts`
- `src/lib/entity-owner.ts`
- Routes under `src/app/api/likes`, `comments`, `shares`
- Mobile: `engagement_provider.dart`, `comment_provider.dart`, `share_provider.dart`, `like_button.dart`, `engagement_action_bar.dart`, `comment_bottom_sheet.dart`, `share_bottom_sheet.dart`

## Counters

| Entity | Columns maintained in the write transaction |
| --- | --- |
| `TripFinalPost` | `likeCount`, `commentCount`, `shareCount` |
| `TripThreadEntry` | `likeCount`, `commentCount` |
| `Comment` | `likeCount` |

`incrementEntityCount` and `decrementEntityCount` in `engagement-utils.ts` update the right table for the entity type. Decrement uses a floor of 0 so a double-delete cannot go negative. Like and in-app share transactions set `maxWait: 15_000` and `timeout: 20_000`.

`invalidateEngagementCache` deletes `{like|comment|share}Count:{entityType}:{entityId}` from memory and Redis. Nothing reads those keys. The number on screen is the column. See [Redis](./09-redis-cache-and-queues.md).

## Likes

`Like` is unique on `(userId, entityType, entityId)`. Indexes: `(entityType, entityId, createdAt)` for "who liked this", and `(userId, createdAt DESC)` for "what this user liked".

`POST /api/likes` creates the row and increments `likeCount` in one transaction. Prisma `P2002` on the unique key returns the existing like. A double tap is idempotent, not a 500.

`DELETE /api/likes` and `DELETE /api/likes/:entityType/:entityId` delete and decrement.

`GET /api/likes/status?entityType=&ids=` accepts up to **100** ids and returns a map. This is the call the feed, the thread page, and the post deeplink share. It is one `findMany` with `entityId IN (...)`.

`GET /api/likes/:entityType/:entityId/users` is the "liked by" list, cursor on like id, profile fields from `USER_FULL_SELECT`.

`GET /api/likes/user/:userId` is that user's like history and uses `(userId, createdAt DESC)`.

Notifications, not awaited:

- Like on a post or entry: type `LIKE`, recipient is the entity owner (`entity-owner.ts`).
- Like on a comment: type `COMMENT_LIKE`, metadata includes `postEntityType`, `postEntityId`, `commentId`, and when known `tripId` or `threadEntryId`.

Self-likes do not notify. `createNotification` drops `actorId === recipientId`.

Rate limits for likes are in `rateLimit.ts` (the like preset is 200 per hour). The mobile `LikeButton` updates `EngagementProvider` optimistically and reconciles with the response.

`Comment` likes go through `POST /api/comments/:commentId/like`, which uses the same like service with `entityType = COMMENT` and increments `Comment.likeCount`.

## Comments

`Comment.contentText` is `VarChar(250)`. Indexes: `(entityType, entityId, createdAt)` for the thread of comments, `(parentCommentId, createdAt DESC)` for replies, `(userId)` for cleanup.

Rules in `comment.ts`:

- A top-level comment targets `TRIP_FINAL_POST` or `TRIP_THREAD_ENTRY`.
- A reply sets `parentCommentId`. `validateParentComment` rejects a parent that is itself a reply. Depth is one.
- Only a top-level comment increments the parent entity's `commentCount`. Replies do not. The reply count on a comment is `_count.replies` at read time, not a column.
- Mentions: `@all` is trip-scoped and expands through `tripTagResolution.ts` to members except the actor. Other `@username` tokens are looked up globally and kept only if `canViewEntity` says that person can see the parent. Each mention is a `TAG` notification.
- A top-level comment notifies the entity owner with type `COMMENT`. A reply notifies the parent author with `COMMENT_REPLY`. Metadata carries `contentPreview`, ids, and trip context so the inbox can route the tap.

`PUT /api/comments/:commentId` edits text. `DELETE` is the author or the owner of the parent entity. Delete cascades replies and likes on those replies, and decrements `commentCount` once for a top-level comment.

`GET /api/comments/entity/:entityType/:entityId` is the list. `GET /api/comments/:commentId/replies` uses the parent index.

The comment rate preset is 15 requests per 15 minutes. That is intentionally tighter than likes.

Mobile: `CommentProvider`, `comments_screen`, and `comment_bottom_sheet.dart`. Tests: `comment_provider_test.dart`, `comment_service_test.dart`, `comments_screen_test.dart`.

## Shares

`Share` columns: `shareToken` unique, `shareType` (`DEEP_LINK`, `WEB_LINK`, `EXTERNAL`), `expiresAt`, `metadata` JSON. Indexes `(userId, createdAt)` and `(entityType, entityId)`.

`ShareSource` is **not** a column. It is a request field: `SYSTEM_SHEET` (default) or `IN_APP_DM` (`src/lib/validation.ts`).

| Source | What the service does |
| --- | --- |
| `SYSTEM_SHEET` | `share.create` only. Does **not** increment `shareCount`. The comment in `share.ts` says this avoids holding a long transaction while the OS sheet is the common path |
| `IN_APP_DM` | Transaction: create plus `incrementEntityCount(..., "shareCount")` |

The Flutter share sheet sends `SYSTEM_SHEET` (`share_service.dart`). `IN_APP_DM` is accepted by the API and covered by tests. The chat UI does not call it yet, so a share from the system sheet does not move the public share counter. That is the current behavior, not an accident to "fix" in the docs.

`createShareSchema` allows create only for `TRIP_FINAL_POST`. Thread entries are liked and commented, and they are not the share-create target.

Token: `nanoid(16)`, up to `ENGAGEMENT_CONSTANTS.SHARE.MAX_RETRY_ATTEMPTS` (10) on collision.

Cache: `shareToken:{token}` in Redis via `getOrSet`. TTL is the time until `expiresAt`, or `CACHE_TTL.SHARE_TOKEN` (1 hour). `resolveShareToken` reads cache then database, and deletes the row if it is past `expiresAt`. `trackShareOpen` appends `{ timestamp, platform, location, userAgent }` onto `metadata.opens` and invalidates the cache key.

`generateDeepLink` uses `DEEP_LINK_BASE_URL` or `tripthread://`, then the lowercased entity type and id.

| Route | Role |
| --- | --- |
| `POST /api/shares` | Create |
| `GET /api/shares/:shareToken` | Resolve |
| `POST /api/shares/track/:shareToken` | Record an open |
| `GET /api/shares/stats/:entityType/:entityId` | Counts |
| `GET /api/shares/user/:userId` | This user's shares. Previews are loaded with `Promise.all` over the distinct posts, entries, and comments, not one query per share |

Share rate preset: 100 per 24 hours.

Web and app links also pass through `src/lib/deeplink.ts` and the nginx `/share` proxy. Universal Links (`/.well-known`) are served by the same process. Wiring them in production is an ops step. The context snapshot still marks that as ops-only.

## Delete consistency

`threadEntryPurge.ts` deletes likes, comments, shares, and notifications for an entry in bulk, then decrements `entryCount`. It does not try to decrement each like one by one. The entry is going away, so its counters go away with it. Final-post delete does the same for the post's engagement. A half-deleted counter cannot be left on a row that no longer exists.
