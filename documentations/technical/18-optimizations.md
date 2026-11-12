# Optimizations

This chapter is only about work that is in the code to make a query, a page, or an external call cheaper or safer under concurrency. Each item says what was slow, what changed, and which request it protects.

## 1. Indexes

Postgres will sequential-scan a small table and look fine. These indexes exist for the queries that grow with trips, threads, and inboxes. They were added in three migrations plus the uniques that shipped with the tables.

### `20261004153000_add_hot_path_query_indexes`

| Index | Columns | Query it serves | What you avoid |
| --- | --- | --- | --- |
| `notifications_recipientId_createdAt_id_idx` | `recipientId`, `createdAt DESC`, `id DESC` | Notification inbox keyset | A sort of one user's whole inbox, and a cursor that cannot use `id` as a tie-break. Replaced a narrower notification index |
| `Like_userId_createdAt_idx` | `userId`, `createdAt DESC` | `GET /likes/user/:id` | Filter on user then a sort of all their likes. Replaced `Like_userId_idx` |
| `Comment_parentCommentId_createdAt_idx` | `parentCommentId`, `createdAt DESC` | Reply list | A scan of every comment to find children of one parent |
| `follows_followeeId_idx` | `followeeId` | Followers list, "who follows this private account" | A scan of `follows` filtered after the fact. The unique pair already helps when `followerId` is the leading column. This index is the other direction |
| `follow_requests_followeeId_status_createdAt_idx` | `followeeId`, `status`, `createdAt DESC` | Pending request inbox | Load every request for a popular private account, then filter `PENDING` |
| `trips_userId_status_idx` | `userId`, `status` | My trips by status, the one-active-trip conflict check | Load every trip I own to find the ongoing one |
| `trips_status_endDate_idx` | `status`, `endDate` | Scheduler end batch | Scan all trips to find `ONGOING` rows whose end has passed |
| `trips_status_startDate_idx` | `status`, `startDate` | Scheduler start batch | Scan all trips to find `UPCOMING` rows whose start has passed |
| `trip_participants_userId_idx` | `userId` | "Trips I joined" on `GET /trips` and live-trip membership | Scan `trip_participants` for one user |
| `trip_thread_entries_tripId_createdAt_id_idx` | `tripId`, `createdAt DESC`, `id DESC` | Thread keyset pagination | Sort an entire trip thread on every page. The `id` column makes the cursor stable when two entries share a timestamp |
| `trip_thread_entries_authorId_createdAt_idx` | `authorId`, `createdAt DESC` | Purge my entries, author history | Find one author's entries by scanning every entry |
| `trip_final_posts_isPublished_createdAt_id_idx` | `isPublished`, `createdAt DESC`, `id DESC` | Home feed | Sort every final post, including drafts, to find the published page. This is the feed index |
| `media_uploadedById_createdAt_idx` | `uploadedById`, `createdAt DESC` | Daily quota (count since UTC midnight) and a user's media | Sum or count a user's media by scanning `media` |

### `20261004180000_add_remaining_hot_path_indexes`

| Index | Columns | Query it serves | What you avoid |
| --- | --- | --- | --- |
| `trips_userId_createdAt_idx` | `userId`, `createdAt DESC` | My trips, newest first, when status is not the filter | Sort all of my trips |
| `media_tripId_idx` | `tripId` | Cover checks, per-trip media cap, trip gallery | Scan `media` for one trip. The cap runs at signature time and would otherwise get slower as the table grows |
| `trip_join_requests_receiverId_status_idx` | `receiverId`, `status` | Invite inbox `GET /users/me/trip-invites` | Scan all invites for a status |
| `conversations_updatedAt_idx` | `updatedAt DESC` | Chat list order | Sort every conversation. Combined with the participant filter, the planner can still choose the user index first on a small account. The index keeps the global "recent rooms" order cheap |

### Spatial migration `20251028181650`

| Index | Columns | Query it serves | What you avoid |
| --- | --- | --- | --- |
| `coordinate_spatial_idx` | `places(lat, lng)` | Resolve and dedupe near a point | Compare a new pin to every place. It is a btree on the pair, not PostGIS. Queries still need a bounding box to use it well. The application builds that box from the type threshold (city 0.03 degrees, district 0.01, POI 0.001) |
| `external_id_idx` | `places(externalId)` | Mapbox feature id to row | Walk places to find one provider id. The column is also `UNIQUE`, which is the real constraint. The named index matches what `place.ts` looks up |
| `trip_visits_idx` | `places_on_trip(tripId, visitedAt)` | Trip place timeline | Sort all visits to find one trip's days |

### Uniques that are also performance and correctness

| Unique | Protects |
| --- | --- |
| `follows (followerId, followeeId)` | One edge, and a fast "do I follow them" |
| `follow_requests (followerId, followeeId)` | One request per pair |
| `likes (userId, entityType, entityId)` | One like. `P2002` is treated as success, so the unique index is the idempotency lock |
| `trip_participants (tripId, userId)` | Membership test on every thread write |
| `trip_final_posts (tripId)` | One draft. Generate is idempotent because the second insert fails and the code returns the row |
| `conversations (tripId)` | One trip room |
| `media.publicId`, `shares.shareToken`, `places.externalId` | External identity |

### Other indexes declared on the models

These shipped with the feature rather than in the hot-path migrations. They are load-bearing.

| Index | Why |
| --- | --- |
| `notifications (recipientId, readAt)` | Unread count and mark-all-read update the null `readAt` slice for one user |
| `jwt_refresh_tokens (userId)`, `(expiresAt)` | Logout-all, and a future expiry sweep |
| `password_resets (userId, expiresAt)` | Invalidate previous unused tokens in one update |
| `security_events` on type+time, user+time, entity | Abuse score and an entity's report history |
| `likes (entityType, entityId, createdAt)` | Liked-by list |
| `comments (entityType, entityId, createdAt)`, `(userId)` | Comment page, account purge |
| `shares (userId, createdAt)`, `(entityType, entityId)` | My shares, share stats |
| `chat_messages (conversationId, createdAt DESC)` | Message page and the unread range |
| `conversation_participants (userId)`, `(userId, lastReadAt)` | My rooms, unread join |
| `trip_expenses (tripId, createdAt)`, `(tripId, deletedAt)`, `(payerId)` | Ledger page, "live expenses only", nets by payer |
| `trip_expense_shares (userId)` | "What do I owe" across expenses |
| `trip_settlements (tripId, createdAt)`, both user ids | Summary and per-user settlement totals |
| `media (chatMessageId)` | Attachments for a message page |

## 2. Removing N+1 queries

An N+1 here means the handler loads a page of N rows and then issues one query per row for a count, a like, or a profile.

| Before this shape | What the code does now | Where |
| --- | --- | --- |
| Count likes per feed card | Read `likeCount` on `TripFinalPost`. The column moves inside the like transaction | `feed/home/route.ts`, `engagement-utils.ts` |
| Count comments and shares per card | `commentCount`, `shareCount` columns, same transaction rule | `like.ts`, `comment.ts`, `share.ts` (`IN_APP_DM` only for the share bump) |
| Count thread entries and members per card | `Trip.entryCount`, `Trip.participantCount`, updated when entries and participants change | Feed, discover rank SQL, live trips |
| "Did I like these 20 posts?" as 20 queries | `checkLikeStatus` one `findMany` with `entityId IN (...)`, cap 100 ids | Home feed, post deeplink, `GET` thread entries, `GET /likes/status` |
| Home feed count and page in series | `Promise.all` of the count query and the page query | `feed/home/route.ts` |
| Discover: hydrate each ranked id alone | Raw SQL returns ids in rank order, then one `findMany({ id: { in } })`, then a `Map` restores the SQL order | `discover/trips/route.ts` |
| Chat list: `COUNT(*)` per conversation | `batchFetchUnreadCounts`, one `GROUP BY conversationId` | `chat.ts` |
| Share history: load the entity once per share | `getSharesByUser` groups ids and `Promise.all`s three `findMany` calls (posts, entries, comments) | `share.ts` |
| Send message: serial auth and reply checks | `Promise.all` of the membership check and the reply lookup | `chat.ts` `sendMessage` |
| Trip participant fan-out on chat sync | `createMany` | `chat.ts` |
| Leave trip and delete every entry one by one | `purgeAuthorThreadEntriesWithClient` uses `deleteMany` for tags, likes, comments, shares, notifications | `threadEntryPurge.ts` |
| Live rail: a query per followee | One trip query `take 60`, then dedup in memory with a map of members | `live-trips/route.ts` |
| Notification inbox: a query per row to learn the trip name | Producers store `tripId`, `tripName`, and `contentPreview` in `metadata`. The list route does not re-walk the graph | `notification.ts` |

Denormalized counters are an optimization only if the write path is the only writer. The entry route increments `entryCount` in the same transaction as the insert. Purge decrements it. A script that deletes entries with raw SQL will make discover ranking lie, because discover sorts on `(entryCount + participantCount)`.

`_count` still appears in a few payloads (reply counts, some live-trip nested counts) where the set is small or the number is not on a column. Reply count is `_count.replies` because replies do not have their own denormalized column and a comment has few replies. That is a bounded N+1 inside Prisma's `include`, which batches, and it is not the feed.

## 3. Pagination

Offset pagination gets slower as you go deeper because the database still walks the skipped rows. Keyset pagination starts at the cursor.

| Surface | Cursor | Order |
| --- | --- | --- |
| Home feed | base64url `{ createdAt, id }` in `feedCursor.ts` | `createdAt DESC, id DESC`. `take limit+1` |
| Thread | base64url `{ c, i }` | Same order, page reversed to chronological for the client. Default 30, max 100 |
| Thread deep link | Context window, default 25, clamp 3–60 | Centered, not a full scan. Client then pages older, at most 8 extra pages |
| Notifications | `{ v, createdAt, id, source }` | Merged follow-requests and notifications. Each source over-fetches `max(limit*3, 50)` |
| Chat messages | `before` message id | `(conversationId, createdAt DESC)`. Default 30, max 100 |
| Likes and comments lists | id cursor | Matching list indexes |
| Discover | Offset | Ranked SQL. Called out because it is the one major list that is still offset. Fine while pages stay shallow. A deep "page 50" would want a keyset on the rank tuple |

Select lists are narrow. Feed and engagement use `USER_PUBLIC_SELECT` / `USER_FULL_SELECT` instead of `include` of the whole user. Password hashes are never in a select. `hasPassword` on `/users/me` is a SQL boolean expression.

## 4. Redis and memory cache

Full key table: [Redis](./09-redis-cache-and-queues.md). The optimization view:

| Cache | TTL | Saves |
| --- | --- | --- |
| Place search `plc:srch:*` | 15 min | Mapbox Geocoding on repeated queries, including nearby GPS buckets |
| Place identity `place:*` | 24 h | Repeat resolve of the same airport or hotel |
| Unread count `notif:unread:*` | 20 s | The badge poll. Deleted on write so it does not hide a new like for the whole TTL |
| Share token | until expiry, else 1 h | A public share open does not hit Postgres on every preview crawler |
| Rate-limit counters | the window | Shared across API processes, and cheaper than a Postgres counter row |
| Memory LRU in front of all of the above | 5 min when filled from Redis, max 1000 | The Redis REST round trip on a hot key |

Stampede control is part of the optimization. `getOrSet` takes `cache-lock:{key}` for 8 seconds so 50 concurrent feed badges do not all run `COUNT(*)`. Place resolve takes `place:resolve:lock:{externalId}` for 8 seconds or a spatial lock for 5 seconds so 50 concurrent "resolve this hotel" calls do not insert 50 rows and then fight the unique index.

The circuit breaker (250 ms deadline, 30 s open, 1 hour backoff on Upstash rate-limit responses) is an optimization of the failure path. A slow Redis used to be able to add its full HTTP timeout to every cached read. Now one failure opens the circuit and the rest hit memory.

What was considered and not cached: the home feed itself. The feed is per user (follows plus public posts plus like-state) and changes when anyone publishes. Caching the SQL page would be a correctness problem. The counters and the index are the feed optimization instead. Engagement count keys in Redis are invalidated and never read. They are not a cache hit.

## 5. API and client behavior

| Choice | Effect |
| --- | --- |
| Cloudinary direct upload | The API does not proxy video bytes. Signature and confirm are small JSON. The 50 MB body goes to Cloudinary |
| Client image cap 1920×1080 quality 85, video 10 min | Less bandwidth before the server ever sees a size |
| Delivery transforms in `cloudinary_utils.dart` (`f_auto,q_auto`, width limit) | The phone downloads a sized image. The stored URL stays original |
| `MediaService` concurrency 3, upload retries 2 | A multi-select of 10 does not open 10 uploads, and a blip does not fail the batch |
| Dio single-flight refresh | A burst of 401s becomes one `/auth/refresh-token`, not N rotations that invalidate each other |
| Expense screen loads summary and the expense page with `Future.wait` | One round trip worth of waiting, two queries |
| Discover search generation token | A slow keystroke cannot overwrite a newer result (wasted render, not a wasted index, but it avoids applying stale data) |
| Chat `touchConversation` is not awaited | The sender's response does not wait for the room's `updatedAt` write. The list order catches up on the next fetch or on the socket event |
| Scheduler is not a queue consumer | Zero Redis commands from cron, so the Upstash budget stays on search, badges, and rate limits. Documented in `scheduler/MIGRATION_NOTES.md` |
| Read-path trip status sync | Users do not wait for the hourly cron to see `ONGOING`, and the cron query stays small because most active trips were already moved when someone opened them |
| Settlement `FOR UPDATE` plus "must match an open edge" | Prevents two payees from recording overlapping transfers. That is correctness, and it also avoids a repair job |
| Fixed-window rate limits fail open | A limiter error does not turn into a Postgres outage caused by retries |

## 6. What is not optimized, on purpose or not yet

- Discover is offset-paginated.
- `GET /users` search has no rate preset and no `deletedAt` filter. It is a `contains` scan on name and username, which will want a trigram index if search traffic grows. There is no `pg_trgm` index today.
- User stats (`tripCount`, `followerCount`, `followingCount`) are live counts, not columns. They are one screen, not a feed, so three counts are acceptable.
- Chat fan-out is in-process. That is the opposite of a scale optimization. It is documented in [Chat](./14-chat.md) so nobody adds a replica and expects messages to arrive.
- The scheduler's final-post insert duplicates the finalizer and writes `DRAFT` instead of `READY`. That is a consistency gap, not a performance win. The duplication exists because the scheduler package cannot import `src/lib/services/tripFinalizer.ts`.
- `invalidateEngagementCache` does not currently remove a read. Leaving it is cheap. Building a reader for those keys would be a second source of truth next to the columns, which is the bug the columns were meant to end.
