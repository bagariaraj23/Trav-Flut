# Thread entries and final posts

While a trip is `ONGOING`, members append a thread. When it ends, the owner gets one `TripFinalPost` per trip, edits it, and publishes it into the home feed.

Primary files:

- `src/app/api/trips/[id]/entries/route.ts`
- `src/app/api/trips/[id]/entries/[entryId]/route.ts`
- `src/app/api/trips/[id]/entries/[entryId]/context/route.ts`
- `src/lib/services/threadEntryPurge.ts`
- `src/lib/services/tripTagResolution.ts`
- `src/lib/services/tripFinalizer.ts`
- `src/app/api/trips/[id]/final-post/route.ts`, `final-post/generate/route.ts`, `publish/route.ts`
- Mobile: `trip_provider.dart`, `trip_thread_screen.dart`, `thread_entry_card.dart`, `final_post_provider.dart`, `final_post_edit_screen.dart`

## Entry types

`ThreadEntryType` is `TEXT`, `MEDIA`, or `LOCATION`. Check-in was removed in migration `20261031120000_remove_checkin_entry_type`. There is no check-in value left in the schema or the client.

| Type | Required payload |
| --- | --- |
| `TEXT` | `contentText` |
| `MEDIA` | `mediaId` of a `Media` row the caller owns, not yet attached or already on this trip |
| `LOCATION` | Coordinates and a place. `placeId` links the canonical `Place`. `locationName` and `gpsCoordinates` are stored on the entry as well |

`TripThreadEntry` also has denormalized `likeCount` and `commentCount`. It does not have `shareCount`. Shares of a thread entry are rows in `shares`, but the home-feed share counter lives on `TripFinalPost`.

Tags are `TripThreadTag`, unique on `(threadEntryId, taggedUserId)`.

## Who can write

`POST /api/trips/:id/entries` requires owner or participant, and the trip must be `ONGOING`. The transaction inserts the entry, the tag rows, and increments `Trip.entryCount`. Tag notifications are fire-and-forget.

`GET` is allowed for a member, or for a follower when the owner is private, or for anyone when the owner is public. The list is cursor-paginated.

`PATCH` edits text only, and only while `ONGOING`. The author has a **15 minute** window (`EDIT_WINDOW_MS = 15 * 60 * 1000`). The trip owner can edit any text entry with no window, as moderation. Outside the window the author gets **400**.

`DELETE` is author or owner, `ONGOING` only. It calls `purgeThreadEntryWithClient`.

## Pagination

`GET /trips/:id/entries?limit=&cursor=`

- Default limit **30**, max **100**.
- Order in the database: `createdAt DESC, id DESC`.
- The page is reversed before it is returned, so the client receives chronological order (oldest of the page first).
- Cursor is base64url JSON `{ c: ISO timestamp, i: id }`.
- Response: `{ items, hasMoreOlder, nextOlderCursor }`.

The index is `(tripId, createdAt DESC, id DESC)`. The cursor predicate matches that order, so Postgres can walk the index instead of sorting the whole thread.

`GET /trips/:id/entries/:entryId/context?contextSize=` builds a window centered on one entry for notification deep links. Default size **25**, clamped to **3–60**. `olderTake = floor((size - 1) / 2)`, and the rest is newer. `hasMoreOlder` is a probe, not a count of the entire thread. The same cursor encoding is used so the client can continue paging older from that window.

`TripProvider` uses page size 30. `loadUntilEntryPresent` calls the context route, then at most 8 older pages, so a deep link does not download the whole thread.

## Tags

The request sends `taggedUsernames`, not user ids. `resolveTaggedUserIdsForTripThread`:

- The literal `all` means every trip member except the actor. Members are `trip.userId` plus every `TripParticipant.userId` (`tripMemberUserIds`). The owner counts even though they are not in the participant table.
- Any other token is a case-insensitive username that must be a member.

Each resolved id becomes a `TripThreadTag` and a `TAG` notification.

## Purge

`threadEntryPurge.ts` is the single delete path, used by entry delete, by "remove my data" on leave, and by account deletion.

For one entry it deletes tags, likes, comments, shares, and notifications that point at the entry, deletes place-share rows, deletes the entry, and decrements `entryCount`. Cloudinary cleanup of the attached media is separate and best-effort.

`purgeAuthorThreadEntriesWithClient` does the same for every entry by that author on the trip, in bulk `deleteMany` calls, so leaving a long trip does not issue one query per entry.

## Final post

`TripFinalPost` is unique on `(tripId, userId)`. Each member has their own draft. Migration `20261111120000_personalized_final_posts` assigns older rows to the trip owner, drops the old `tripId` unique index, and adds `(userId, isPublished, publishedAt)` plus `tripId`.

Ending a trip drafts a post for the owner and every current participant (`generateFinalPostsForMembers`). The first draft uses that person's notes, photos they uploaded or posted, and photos on entries that tag them. After that, the editor can add any photo from the trip. The picker numbers the selection and stops at 10 (`FinalPostProvider.maxPhotos`). The home feed and the post screen show `post.user`, the author, and a published post follows that author's privacy. A block in either direction hides that post from the other person's feed and from `canViewEntity`. A draft stays visible only to its author (`canViewEntity` in `src/lib/auth/permissions.ts`).

| Column | Role |
| --- | --- |
| `summaryText` | Generated narrative. Publish requires at least 50 characters |
| `curatedMedia` | Up to 10 image URLs, chosen with a per-day cap so one day does not fill the post |
| `caption` | Editable. Generation adds hashtags |
| `coverMediaUrl` | Optional cover |
| `generationStatus` | `DRAFT`, `GENERATING`, `READY`, `PUBLISHED`, `FAILED` |
| `isPublished`, `publishedAt` | Feed eligibility |
| `likeCount`, `commentCount`, `shareCount` | Denormalized |

`GENERATING` and `FAILED` are on the enum and on the Flutter model. `tripFinalizer.ts` does not assign them. The live values are `DRAFT` (scheduler default), `READY` (API generator), and `PUBLISHED`.

### When a row is created

| Event | Writer | Status |
| --- | --- | --- |
| Scheduler end batch | Inline insert in `scheduler/src/tripStatus.ts`, one row per member who does not already have a post | `DRAFT` (column default). Personal photos, capped at 6. The summary is shorter than the API generator |
| Read-path sync that ends a trip | `TripFinalizerService.generateFinalPostsForMembers` | `READY` |
| `POST /trips/:id/end` from `ONGOING` | same service, one post per member | `READY` |
| `POST /trips/:id/end` from `UPCOMING` | none | No row |
| `POST /trips/:id/final-post/generate` | that member, trip must be `ENDED` | `READY`. Idempotent if their row exists |

`generateFinalPost` is idempotent: if the row exists it returns it instead of overwriting the owner's edits.

### Edit and publish

| Route | Rule |
| --- | --- |
| `GET /trips/:id/final-post` | The caller's own post. A member, or someone who already has a post on this trip |
| `PUT /trips/:id/final-post` | The author edits their draft. If it is already `PUBLISHED`, the status stays `PUBLISHED` |
| `DELETE /trips/:id/final-post` | The author. Removes their post and its engagement rows |
| `POST /trips/:id/publish` | The author. Summary at least 50 characters, and at least one curated media item or a cover URL. Sets `isPublished`, `publishedAt`, `generationStatus = PUBLISHED` |

Publishing the post is what puts it on the home feed. Ending the trip does not publish it. `isPublished` plus `(createdAt DESC, id DESC)` is the feed index. See [Feed](./11-feed-discover-posts.md).

`GET /api/posts/TRIP_FINAL_POST/:id` is the deeplink reader. `TRIP_THREAD_ENTRY` on that route returns **404** ("not supported for direct view"). Thread entries are opened inside the trip, through the context endpoint.

### Mobile

`FinalPostProvider` loads the signed-in member's draft, calls generate if it is missing, autosaves with a debounce, and publishes via `POST /trips/:id/publish`. `toggleMedia` appends in selection order and refuses an 11th photo. The screen is `final_post_edit_screen.dart`. `PhotoOrderBadge` in `media_seek.dart` draws the number.

## Engagement on both kinds of post

Likes and comments target `EntityType` `TRIP_FINAL_POST` or `TRIP_THREAD_ENTRY`. Counters move inside the like or comment transaction. The feed never counts likes per card. See [Engagements](./12-engagements.md).
