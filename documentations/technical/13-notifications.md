# Notifications

One inbox mixes two sources: rows in `notifications`, and pending follow requests that are not notification rows at all.

Primary files:

- `prisma` model `Notification`
- `src/lib/services/notification.ts`
- `src/app/api/users/me/notifications/route.ts`
- `src/app/api/users/me/notifications/unread-count/route.ts`
- `src/app/api/users/me/notifications/read/route.ts`
- `src/app/api/users/me/notifications/[id]/read/route.ts`
- Mobile: `user_provider.dart`, `unified_notification.dart`

## Model

| Column | Role |
| --- | --- |
| `type` | `LIKE`, `COMMENT_LIKE`, `COMMENT`, `COMMENT_REPLY`, `TAG`, `FOLLOW` |
| `actorId` | Who did it. Cascade on user delete |
| `recipientId` | Whose inbox. Cascade on user delete |
| `readAt` | Null means unread |
| `entityType`, `entityId` | Optional pointer at a post, entry, or comment |
| `metadata` | JSON. The inbox flattens known keys |

Indexes:

- `(recipientId, createdAt DESC, id DESC)` is the inbox keyset. Migration `20261004153000` replaced a narrower notification index with this one so the cursor can use `id` as a tie-break.
- `(recipientId, readAt)` is the unread count and "mark all read".

`FOLLOW_REQUEST` is not a `NotificationType`. The service reads `follow_requests` where `followeeId` is the user and `status` is `PENDING`, and emits a synthetic item. Accepting or rejecting the request removes it from the inbox without a notification update, because the row was never in `notifications`.

## Producers

All of these call `createNotification` and do not await it on the user's request path, except where the follow route already finished its transaction.

| Event | Type | Recipient | Where |
| --- | --- | --- | --- |
| Like on a final post or thread entry | `LIKE` | Entity owner | `like.ts` |
| Like on a comment | `COMMENT_LIKE` | Comment author | `like.ts` |
| Top-level comment | `COMMENT` | Entity owner | `comment.ts` |
| Reply | `COMMENT_REPLY` | Parent comment author | `comment.ts` |
| `@username` or `@all` | `TAG` | Each mentioned member who can view the entity | `comment.ts`, thread tag path |
| Public follow | `FOLLOW` | The followee | `POST /follow/:userId` |
| Private follow request | none | The request row is the inbox item | `follow_requests` |

`createNotification` returns immediately when `actorId === recipientId`, and when `blockEitherWay(actorId, recipientId)` is true. It then deletes Redis key `notif:unread:{recipientId}` so the badge is not stuck for the 20 second TTL. Blocking also deletes that key for both people.

Metadata keys the inbox understands: `postEntityType`, `postEntityId`, `commentId`, `parentCommentId`, `tripId`, `tripName`, `threadEntryId`, `contentPreview`. They are copied onto the DTO so the client can route a tap without a second round trip per row.

There is no push transport. No APNs, no FCM. The badge is polling `unread-count`. Offline push is called out as deferred next to chat in `context.json`.

## Read path

`getMergedNotifications`:

1. Fetch pending follow requests and notification rows in parallel. Actors and requesters in a block with the recipient, either direction, are excluded. Restrict does not filter the inbox.
2. Each source is limited to `max(limit * 3, 50)` so a flood of one type cannot starve the merge, while still filling a page.
3. Sort by `createdAt`, then by source rank (`FOLLOW_REQUEST` before `NOTIFICATION` at the same timestamp), then by `id`.
4. Cursor is base64 JSON `{ v, createdAt, id, source }`. Versioned so the merge order can change later without reusing an old cursor.

`GET /api/users/me/notifications?limit=&cursor=`. Limit 1–50. Preset `read_hot`.

`GET .../unread-count` uses `getOrSet` with TTL **20,000 ms**. The loader counts notifications with `readAt` null whose actor is not soft-deleted and is not in a block with the recipient. Follow requests are **not** in that number. The mobile provider treats the badge as engagement-unread and loads requests separately, which matches the API comment in `user_provider.dart`.

`PUT .../read` sets `readAt` on every unread row for the caller and clears the cache key.

`PUT .../:id/read` sets `readAt` on one row the caller owns.

Marking a follow request is not a notification read. Accept and reject are the follow routes. See [Follow](./04-follow-system.md).

## Why the merge exists

A private-account request has to show up in the same list as likes, but it has its own lifecycle (pending, accepted, rejected) and its own table. Writing a duplicate `Notification` row would drift: accept would have to delete or rewrite the notification, and a unique follow request could produce two badges. Reading both tables and sorting in memory keeps one source of truth for each kind of item. The `* 3` over-fetch is the cost of merging two ordered streams without a SQL `UNION` that would have to fake a type column.

The unread cache is short on purpose. A 20 second badge is cheap (one Redis get, and the SQL count only on miss), and every write deletes the key, so the common case after you like someone is a fresh count on their next poll.
