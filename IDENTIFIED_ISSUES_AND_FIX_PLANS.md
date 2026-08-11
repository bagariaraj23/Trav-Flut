# TripThread – Identified Issues & Fix Plans (Rajasthan Trip Testing)

This document lists production issues and feature requests observed during the Rajasthan trip (3 users, Feb 22 – Mar 4, 2026). It references `context.json` and `infra_scalability_analysis.md` for architecture. Fix plans are proposed for review before implementation.

**PRs already merged that addressed some items:** [PR #39](https://github.com/bagariaraj23/Trav-Flut/pull/39), [PR #40](https://github.com/bagariaraj23/Trav-Flut/pull/40), [PR #41](https://github.com/bagariaraj23/Trav-Flut/pull/41), [PR #42](https://github.com/bagariaraj23/Trav-Flut/pull/42), [PR #43](https://github.com/bagariaraj23/Trav-Flut/pull/43) (prod fixes: discover, thread CRUD, pagination, plus follow-ups for **participant leave**, **comment UX**, **15‑minute text edit**, **entry purge**, **final-post card / owner menu**, **share links + shareCount rules** — see sections below).

---

## Legend


| Status         | Meaning                                    |
| -------------- | ------------------------------------------ |
| **Done**       | Addressed in merged PRs (39–43) or earlier |
| **Open**       | Not yet fixed; fix plan below              |
| **Regression** | Worked before; likely broken by recent PRs |



| Area          | Scope                                 |
| ------------- | ------------------------------------- |
| **Backend**   | Next.js API, Prisma, services         |
| **Mobile**    | Flutter screens, providers, services  |
| **Scheduler** | Cron service (trip status / finalize) |


---

## 1. Settings & Account

### Issue 1 – Add account public/private toggle in settings screen

**Status:** Done  
**PR:** #40 (Settings: add account public/private toggle with PATCH privacy).

---

### Issue 9 – Log out of all devices not working

**Status:** Partially addressed (Apr 2026)  
**Area:** Backend + Mobile  
**Description:** "Log out from all devices" only logs out current device; other devices still have access.

**Root cause (hypothesis):**  

- Backend: `POST /auth/logout` with `logoutAll: true` calls `revokeAllRefreshTokens(userId)` and invalidates all refresh tokens in DB. So server-side revocation is in place.  
- Other devices still hold a valid access token in memory and may have a refresh token in secure storage. They are not told to clear auth until they next call an API and get 401 (e.g. when access token expires and refresh fails because it was revoked).

**Fix plan:**  

1. **Backend:** Confirm `revokeAllRefreshTokens` deletes all `JWTRefreshToken` rows for the user. Ensure no caching of token validity.
2. **Mobile:** On any 401 from API (or from refresh-token endpoint), clear local auth completely (tokens + user state) and redirect to login. That way when server revokes all tokens, every other device will get 401 on next request and auto-logout.
3. **Mobile:** After calling logout with `logoutAll: true`, clear local tokens and navigate to login; no extra round-trip needed for current device.
4. **Optional:** Shorter access-token TTL in dev/staging so "logout all" effect is visible sooner on other devices.

**Files to touch:**  

- `src/lib/services/token.ts` (verify revokeAllRefreshTokens).  
- `mobile/lib/services/api_service.dart` or Dio interceptor (on 401 → clear auth + go to login).  
- `mobile/lib/providers/auth_provider.dart` (logout: clear state; ensure 401 path also clears state).  
- `mobile/lib/services/storage_service.dart` (clear tokens on logout).

**Update (Apr 2026):** `TripService` now registers the same `forceLogout` callback as `ApiService` when token refresh fails after 401, so trip APIs also sign the user out session-wide on revoked refresh tokens.

---

## 2. Notifications & Follow

### Issue 2 – Notifications not showing for public users follow/unfollow

**Status:** Done (Apr 2026)  
**PR:** #41 (prior groundwork); **follow-up:** `FOLLOW` added to Prisma `NotificationType`, `POST /follow/[userId]` creates a `FOLLOW` notification on successful public follow, merged notifications + mobile list/tap handle `FOLLOW`.

**Fix plan (if still missing):**  

- Backend: Ensure when a public user is followed, a FOLLOW notification is created and returned in `getMergedNotifications`.  
- Mobile: Notifications screen shows FOLLOW tile and tap navigates to actor profile.  
- If still not showing: verify notification creation in follow API and that mobile filters/display include FOLLOW type.

---

### Issue 3 – Update stats (follow/follower) realtime in profile page

**Status:** Done (Apr 2026)  
**PR:** #41 (prior); **follow-up:** `UserProvider.invalidateUserCache(userId)` added; profile follow flow calls it, refetches profile, reloads profile trips, and refreshes Discover.

**Fix plan (if still stale):**  

- After follow/unfollow/accept, call `UserProvider.invalidateUserCache(viewedUserId)` then `loadProfileData` so avatar and follower/following counts refresh.  
- Confirm no caching of stats that ignores invalidation (e.g. metadata cache in #41 should be invalidated for that user).

---

### Issue 4 – Follow request screen back gesture closes app

**Status:** Done (Apr 2026)  
**PR:** #40 (Follow requests: use BackButton for proper back gestures).

**Description:** Secondary/tertiary screens’ back should go to previous screen or home, not exit app.

**Fix plan:**  

- Use `BackButton` / `PopScope` with `canPop: true` and explicit `onPopInvokedWithResult` where needed so back goes to previous route.  
- Ensure Follow Requests screen pops to Profile (or caller), not system back.  
- Align with Issue 26 (global back behaviour): from any secondary screen, first back → home or previous; only from home, back → exit dialog.

**Files:** `mobile/lib/screens/profile/follow_requests_screen.dart`, `main.dart` (GoRouter), any other tertiary screens.

**Update (Apr 2026):** Follow Requests uses `PopScope(canPop: false)` and always `pop()` or `go('/home')` so the system does not treat the route as “nothing to pop” and exit the app.

---

### Issue 12 – After follow, DP not visible and trips not visible

**Status:** Done (Apr 2026)  
**Area:** Mobile + Backend  
**Description:** After follow is accepted, profile picture and trips of the followed user don’t show.

**Root cause (hypothesis):**  

- DP: Cache or response not including `avatarUrl` after follow; or invalidation not refetching.  
- Trips: Profile for "other user" may not be loading that user’s trips at all (see Issue 23/40).

**Fix plan:**  

1. **Backend:** Ensure `GET /users/[id]` returns `avatarUrl`. Ensure follow/unfollow does not clear or overwrite avatar.
2. **Mobile:** After follow/unfollow, invalidate that user’s cache and refetch profile + stats (per #41). Ensure profile screen for "other user" requests trips for that user (see Issue 23).
3. **Review:** All code paths that touch follow state and that update or read user/profile data (follow API, UserProvider, ProfileScreen, TripProvider when viewing other user).

**Update (Apr 2026):** Profile loads `GET /users/[id]/trips` after follow; cache invalidation + Discover refresh; `ApiService.getUserTrips` accepts array or `{ items }` for `/trips`.

---

## 3. Trip Creation, Dates & Scheduler

### Issue 5 – Update trip cover anytime (fixed but introduced Issue 18)

**Status:** Done (Apr 2026)  
**PR:** #40 (trip cover update for ongoing and ended trips).  
**Regression:** Trip cover upload broken on-trip or after end (Issue 18).

**Fix plan:** Fix cover upload (Issue 18) while keeping "update anytime" behaviour. See Issue 18.

**Update (Apr 2026):** Backend `PATCH /trips/[id]/cover` allows `ONGOING` and `ENDED`; mobile trip detail cover editing gated the same way.

---

### Issue 6 – Option to extend trip (move end date)

**Status:** Open  
**Area:** Backend + Mobile  
**Description:** Allow moving end date for pre-created, date-fixed trips (before they end).

**Fix plan:**  

1. **Backend:** Add `PATCH /trips/[id]` or dedicated `PATCH /trips/[id]/dates` accepting `endDate` (and optionally `startDate`). Validate: endDate >= startDate; trip not yet ENDED; only owner can change.
2. **Mobile:** Trip detail/settings: add "Extend trip" or "Change end date" with date picker, call PATCH.
3. **Scheduler:** Scheduler uses DB dates; no change needed if it reads `endDate` from DB.

**Schema:** Trip already has `startDate`, `endDate`. No migration needed unless you add timezone fields (Issue 8).

---

### Issue 7 – Start/end date not compulsory; dynamic start/end

**Status:** Open  
**Area:** Backend + Mobile  
**Description:** Fewer clicks on trip creation. Start = on "Create trip" click; end = on "End trip" click. Dates optional.

**Fix plan:**  

1. **Backend:** Make `startDate`/`endDate` optional on Trip. On create, if not provided set `startDate = now()` and leave `endDate` null. Trip status can be ONGOING immediately. When user clicks "End trip", set `endDate = now()` and transition to ENDED.
2. **Scheduler:** Only auto-transition trips that have both dates set; skip or treat null-endDate as "manual end only".
3. **Mobile:** Create-trip flow: make dates optional; add "Start now" / "End when I say" options.
4. **DB:** Migration to allow null `startDate`/`endDate` if currently required.

---

### Issue 8 – Start time and end time (user timezones); scheduler at midnight local

**Status:** Open  
**Area:** Backend + Scheduler  
**Description:** Trip "starts" 20 Mar 2026 IST should become ONGOING at 20 Mar 00:00 IST, not when scheduler runs at 05:30 IST.

**Fix plan:**  

1. **Schema:** Add optional `startTimeTimezone` and `endTimeTimezone` (e.g. IANA string) to Trip, or store start/end as timestamp-with-timezone.
2. **Scheduler:** Run more frequently (e.g. every 15 min) or at hour boundaries; compare trip’s start/end in their timezone to "now" in UTC and transition. Alternatively, store UTC equivalents at trip create/update so scheduler can compare in UTC.
3. **Backend:** When creating/updating trip, convert user’s local start/end to UTC and store, or store local + timezone and compute UTC in scheduler.
4. **Docs:** Document in `infra_scalability_analysis.md` or scheduler README that trip dates are interpreted in trip timezone (or UTC if not set).

**Files:** `prisma/schema.prisma`, `scheduler/src/tripStatus.ts`, trip create/update API.

---

## 4. Navigation, Home, Discover

### Issue 10 – Replace search with DM icon (feature in progress)

**Status:** Done (placeholder, Apr 2026)  
**Description:** Home page: replace search with DM icon for upcoming DM feature.

**Fix plan:** UI-only: swap home app bar search icon for DM icon; route to placeholder or "Coming soon" until DM is ready.

**Update (Apr 2026):** Feed app bar uses chat-bubble icon and a “coming soon” snackbar.

---

### Issue 11 – Continue & Replace trip: replace previous upcoming trip

**Status:** Open  
**Area:** Backend + Mobile  
**Description:** If user "continues & replaces", delete previous upcoming trip if it hasn’t started; if it has started, end it normally.

**Fix plan:**  

1. **Backend:** Define "replace" semantics: e.g. `POST /trips/replace` or flag on create that finds current user’s UPCOMING (or ONGOING) trip and either (a) delete if UPCOMING, or (b) end if ONGOING, then create new trip. Implement in a transaction.
2. **Mobile:** "Continue & Replace" button calls this API then navigates to new trip.

---

### Issue 12 (duplicate) – UX: redirect to thread for participants; bubble for all

**Status:** Done (Apr 2026)  
**Description:** Auto-redirect to thread and floating bubble are only for trip owner; participants should get the same.

**Fix plan:**  

1. **Mobile:** When app opens (or home loads), if current user has an ONGOING trip as **participant** (not only owner), apply same logic: redirect to that trip’s thread once, and show floating bubble (Home ↔ Thread).
2. **Data:** Use existing `GET /trips` (returns trips where user is owner or participant); filter for status ONGOING and use first one for redirect/bubble.
3. **Files:** `main.dart` or home screen init, and the widget that shows the bubble (ensure it checks "has any ongoing trip" not "is owner of ongoing trip").

**Update (Apr 2026):** `GET /trips/status` returns an ongoing trip if the user is owner **or** participant; home redirect and bubble use `TripProvider.currentTrip` as before.

---

### Issue 13 – Discover page not updated; trips not showing (ONGOING/ENDED)

**Status:** Done (Apr 2026)  
**PR:** [#43](https://github.com/bagariaraj23/Trav-Flut/pull/43)  
**Area:** Backend + Mobile  

**Description:** Discover did not show ongoing or completed trips reliably.

**Root cause:** Backend logic was already correct; mobile `FeedProvider` filtered out trips when `user.isPrivate && !isFollowing` while the API never sent `isFollowing` per trip, which dropped **followed private** owners’ trips. Pagination also set `hasNext` false when a page parsed to zero rows even if the server had more pages.

**Fix applied:**  

1. **Mobile:** `loadDiscoverTrips` adds all parsed trips (server already restricts to followed + public trip owners). `hasMoreDiscoverTrips` follows server `hasNext` only.  
2. **Backend:** `GET /discover/trips` includes `isFollowing: followedUserIds.includes(trip.userId)` on each trip for future client use.  
3. **Related:** Profile follow flow still refreshes discover (`loadDiscoverTrips(refresh: true)`) per PR #41.

---

## 5. Thread Entries & Map

### Issue 13 (list) – Delete thread entries

**Status:** Done (Apr 2026)  
**PR:** [#43](https://github.com/bagariaraj23/Trav-Flut/pull/43)  
**Area:** Backend + Mobile  

**Description:** Delete wrong thread entries; remove media from Cloudinary; location pins drop from map when the thread row is removed.

**Implemented:**  

1. **Backend:** `DELETE /trips/[id]/entries/[entryId]` — author or trip owner, trip `ONGOING` only; cleans likes, comments, shares, notifications, `PlaceShare`; decrements `trip.entryCount`; removes linked `Media` + Cloudinary when unused; clears `coverMediaId` if it pointed at deleted media. Hard delete on `TripThreadEntry` (map GET reads live thread rows — pin disappears). Canonical `Place` rows are not deleted globally.  
2. **Backend:** `PATCH` same route — **TEXT** entries only; `contentText` via `patchThreadEntryTextSchema`.  
3. **Mobile:** Long-press entry → sheet: Delete (moderators) / Edit text (text only); `TripService` + `TripProvider`; `EngagementProvider.clearEntity` on delete.

---

### Issue 14 – Edit/update thread entry (text within 15 min for author, or delete; location edit TBD)

**Status:** Partial (Apr–May 2026) — text + delete + **15m author** rule shipped (PR #43 follow-ups); **in-place location/check-in edit** still open  
**PR:** [#43](https://github.com/bagariaraj23/Trav-Flut/pull/43)  
**Area:** Backend + Mobile  

**Description:** Wrong location or text on a thread entry.

**Delivered:** Delete any entry type (ongoing trip), including location rows (map pin drops). Edit **text** via `PATCH /trips/[id]/entries/[entryId]`.  

**Update (Apr–May 2026):** **Authors** may edit **text** only within **15 minutes** of `createdAt` (backend `PATCH` + mobile sheet). **Trip owner** (non-author) may still edit text after that for moderation. Location/check-in **in-place** edit remains future work.

---

### Issue 15 – Realtime thread entry updates

**Status:** Open  
**Area:** Architecture  
**Description:** When a participant adds an entry, others don’t see it until they leave and re-open the thread.

**Fix plan:**  

1. **Polling:** Easiest: on thread screen, poll `GET /trips/[id]/entries` every N seconds (e.g. 15–30) when screen is visible; or "Pull to refresh".
2. **WebSockets/SSE:** Add WebSocket or SSE endpoint for "trip entries" and have mobile subscribe when thread screen is open; push new entries. Backend must broadcast on POST entry.
3. **Webhooks:** Webhooks are for external systems; not for in-app realtime. Use polling or WebSockets/SSE for in-app UX.
4. **Recommendation:** Start with polling or short-interval refresh; add SSE/WebSocket later if needed (see `infra_scalability_analysis.md` for scale).

---

### Issue 16 – Scroll to latest thread entry; paginate (latest 10, then cursor backward)

**Status:** Done (Apr 2026)  
**PR:** [#43](https://github.com/bagariaraj23/Trav-Flut/pull/43)  
**Area:** Backend + Mobile  

**Description:** Thread opened at oldest entries; should anchor to latest and load older on scroll up without loading the full history.

**Implemented:**  

1. **Backend:** `GET /trips/[id]/entries` returns a page object `{ items, hasMoreOlder, nextOlderCursor }`. Default fetch: newest `limit` rows (default 30, max 100), reversed to **chronological ascending** for the client. **`cursor`** = base64url JSON `{ c: ISO createdAt, i: entryId }` for stable composite pagination (not offset).  
2. **Mobile:** `ThreadEntriesPage`, `TripProvider.loadCurrentTripEntries` / `loadOlderThreadEntries` / `loadUntilEntryPresent` (for notification `highlightEntryId`). Thread screen: initial **jump to bottom** (double post-frame); scroll-near-top loads older with **scroll offset preservation**; no mid-fetch header that would change extent before prepend.  
3. **API compat:** `ApiService` GET entries accepts legacy `data` array or new `data.items`.

---

## 6. Media & Trip Cover

### Issue 18 – Trip cover image upload not working (on trip or after ended)

**Status:** Done (Apr 2026)  
**Area:** Backend + Mobile  
**Description:** Cover upload used to work; broken after recent PRs (e.g. #40).

**Fix plan:**  

1. **Backend:** `PATCH /trips/[id]/cover` allows owner and participants (per code). Verify: (a) multipart or JSON with mediaId is accepted; (b) no 403 for participants; (c) after update, `coverMediaId` is set and returned. Check for regression in permission check (e.g. only owner allowed by mistake).
2. **Mobile:** Ensure cover update flow sends the same payload as before (e.g. after Cloudinary upload, confirm media then PATCH trip cover with `coverMediaId`). Check that trip cover PATCH is called for ongoing/ended trips (PR #40 intended to allow that).
3. **Regression check:** Compare current cover route and mobile flow with pre–PR#40 version; restore behaviour for participants and for ongoing/ended trips.

**Files:** `src/app/api/trips/[id]/cover/route.ts`, `mobile/lib/...` (trip cover upload flow).

**Update (Apr 2026):** Cover route allows `ONGOING` and `ENDED`; trip detail allows cover edit for both statuses when user is owner or participant.

---

### Issue 19 – Avatar not changing per Google DP on OAuth login (works sometimes)

**Status:** Open  
**Area:** Backend + Mobile  
**Description:** OAuth login should set avatar from Google; sometimes it doesn’t.

**Fix plan:**  

1. **Backend:** In Google OAuth callback, always fetch Google profile picture URL and set/update `User.avatarUrl` on create and on every login (or at least when missing). Ensure no race (use transaction or unique user lookup).
2. **Mobile:** After login, refetch `/users/me` so avatar is fresh. If backend sets avatar from Google, one refetch is enough.
3. **Caching:** Ensure avatar is not cached indefinitely; invalidate on login or use short TTL for profile.

**Files:** `src/lib/services/googleAuth.ts`, `src/app/api/auth/google/route.ts`, mobile auth flow.

---

## 7. Profile & Participants

### Issue 20 – Trip participants can exit trip (data persist or wipe)

**Status:** Done (Apr–May 2026)  
**Area:** Backend + Mobile  
**Description:** Participant can leave trip; option to keep their data or remove it.

**Fix applied:**  

1. **Backend:** `POST /trips/[id]/leave` with body `{ removeMyData: boolean }`. **Not** trip owner; must be a **TripParticipant**. Removes participant row, decrements **`participantCount`**, clears **pending** join requests for that user. If **`removeMyData: true`**, purges all **author’s** thread entries on that trip (same cleanup as `DELETE` entry: comments, likes, shares, notifications, `PlaceShare`, `entryCount`, Cloudinary when safe) — **only while trip is `ONGOING`**; otherwise 400. If **`false`**, entries stay; no schema soft-delete field added.
2. **Mobile:** **`TripService.leaveTrip` / `TripProvider.leaveTrip`**. **Participants** screen: App bar **Leave trip** + dialog (**Keep my entries** vs **Remove my entries**). **Trip detail:** **Leave trip** for non-owner participants (upcoming / ongoing / ended). Navigate to **`/trips`** on success.
3. **Refactor:** `src/lib/services/threadEntryPurge.ts` — `purgeThreadEntryWithClient` + `cleanupThreadEntryMedia`; used by **DELETE** entry and **leave** (batch).

---

### Issue 21 – Trip owner bubble overlapping "+" create entry button; order +, camera, bubble

**Status:** Partially addressed (Apr 2026)  
**Area:** Mobile  
**Description:** FAB order should be: + (create entry), camera, trip owner bubble.

**Fix plan:** In `trip_thread_screen.dart` (or wherever FABs are), reorder children and adjust layout so the three buttons are in that order and don’t overlap. Use a small vertical or horizontal stack with spacing.

**Update (Apr 2026):** Trip detail app bar actions reordered to **Add entry** then **cover camera**. `FloatingTripNavButton` default position is bottom-right with extra reserve on thread vs home so it clears the composer and bottom nav.

---

### Issue 22 – Too many icons on profile; re-organize (follow requests, trip invites)

**Status:** Open  
**Area:** Mobile  
**Description:** Profile has too many icons; need better placement for follow requests and trip invites.

**Fix plan:** Move follow-requests and trip-invites into a single "Requests" or "Activity" entry (e.g. one icon that opens a bottom sheet or second screen with two sections), or place them under a menu. Keep settings and logout prominent. Align with PR #41 (mail icon on own profile only).

---

### Issue 23 – Trips not shown for other users when opening their profile

**Status:** Done (Apr 2026)  
**Area:** Backend + Mobile  
**Description:** When viewing another user’s profile, their trips don’t show (including for following/public users and trip participants).

**Root cause:**  

- `GET /trips` returns trips for the **authenticated** user (owner or participant). There is no `GET /users/[id]/trips` for "trips belonging to user X".  
- Profile screen for "other user" likely doesn’t load that user’s trips; it may show current user’s trips or nothing.

**Fix plan:**  

1. **Backend:** Add `GET /users/[id]/trips`. Return trips where `userId = id` (trips owned by that user). Apply visibility: if viewer is not the user and user is private, return 403 or empty; if viewer follows user or user is public, return their trips. Optionally include trips where they are participant (so "Raj’s profile" shows trips he’s in). Paginate.
2. **Mobile:** On ProfileScreen for other user, call `GET /users/[userId]/trips` (or equivalent) and display in profile. Use same trip card as discover/profile.
3. **Cache:** Invalidate or key by `userId` so different profiles don’t share the same list.

**Files:** New route `src/app/api/users/[id]/trips/route.ts`, `mobile/lib/services/api_service.dart`, `mobile/lib/providers/user_provider.dart` or `trip_provider.dart`, `profile_screen.dart`.

**Update (Apr 2026):** Implemented `GET /users/[id]/trips` (privacy + owned/joined trips), `ApiService.getTripsForUser`, profile screen list + navigation.

---

### Issue 25 – View other users’ profile picture (click to enlarge)

**Status:** Done (Apr 2026)  
**Area:** Mobile  
**Description:** Only own profile picture is clickable; others should be too.

**Fix plan:** In profile screen and any avatar list (comments, participants), wrap other users’ avatars in a GestureDetector/InkWell that opens a full-screen dialog or route with the image (avatarUrl). Reuse the same viewer as for own profile.

**Update (Apr 2026):** Profile header avatar opens full-screen zoom when `avatarUrl` is set (any profile).

---

### Issue 27 – View participants feature; show list to other participants

**Status:** Done (Apr 2026)  
**Area:** Backend + Mobile  
**Description:** Participants should see who else is in the trip.

**Fix plan:**  

1. **Backend:** `GET /trips/[id]/participants` already exists; ensure it allows **participants** (not only owner) to read the list.
2. **Mobile:** Trip detail or thread screen: add "Participants" entry that navigates to participants list (reuse or mirror existing participants screen). Show for both owner and participants.

**Update (Apr 2026):** Trip detail shows **View Participants** / **Manage Participants** for non-owner participants (ongoing and ended); owner still has End Trip.

---

## 8. Final Post

### Issue 24 – View/publish final post button not showing on old posts

**Status:** Done (Apr 2026)  
**Area:** Mobile + Backend  
**Description:** For older ended trips, the trip detail screen only showed "View Final Post" when `finalPost` was embedded on the trip object; trips ended by the scheduler (or without a row) had no CTA.

**Fix applied:**  

1. **Mobile:** For **ended** trips, **owners** always see **Create Final Post** or **View Final Post** (no longer gated on `trip.finalPost != null` alone). Participants still see **View Final Post** only when a draft exists.  
2. **Backend:** `POST /trips/[id]/final-post/generate` — owner only, trip must be `ENDED`; calls `TripFinalizerService.generateFinalPost` (idempotent).  
3. **Mobile:** `FinalPostProvider.loadDraft` calls generate when `GET` returns `Final post not found`, then loads the draft.

---

### Issue 28 – View final post returns 403 for participants

**Status:** Done (Apr 2026)  
**Area:** Backend  
**Description:** Only trip owner can view final post; participants get 403.

**Root cause:** `GET /trips/[id]/final-post` uses `ensureOwner(tripId, userId)`; only owner can read.

**Fix plan:**  

1. **Backend:** Change GET final-post to allow **owner or participant**. Keep PUT (edit) and publish for owner only. In final-post GET handler: load trip with participants; if `trip.userId === userId` or participant list contains userId, return final post; else 403.
2. **Mobile:** No change if backend starts returning 200 for participants.

**Files:** `src/app/api/trips/[id]/final-post/route.ts` (replace `ensureOwner` for GET with owner-or-participant check).

**Update (Apr 2026):** GET uses `ensureCanReadFinalPost`; PUT still uses `ensureOwner`.

---

### Issue 29 – Final post generation uses "your trip" instead of trip name

**Status:** Done (Apr 2026)  
**Area:** Backend + Scheduler  
**Description:** Caption / summary used "your trip" when destinations were empty, ignoring the trip title from create-trip.

**Fix applied:**  

1. **`TripFinalizerService`:** `buildSummary` uses `trip.title` when there are no destination strings; opening line avoids "through …" duplication when destinations are empty. `generateDefaultCaption` prefers `destinations[0]`, then `trip.title`, then `"your trip"`.  
2. **`scheduler/src/tripStatus.ts`:** `findMany` selects `title`; summary/caption use `title` when destinations are empty (`titleTrim || destLabel` for caption).

---

### Issue 30 – Draft: image order changeable; order of selection = order in post

**Status:** Open  
**Area:** Backend + Mobile  
**Description:** In final post draft, user should reorder selected images; order of selection should define order in post.

**Fix plan:**  

1. **Backend:** Final post stores ordered list of media IDs (e.g. `mediaIds: string[]` or ordered relation). PUT final-post accepts ordered array; persist order.
2. **Mobile:** Draft screen: show selected media as reorderable list (e.g. drag handles); send order in PUT.
3. **Schema:** If TripFinalPost has a single cover or a fixed set of media, add a field or relation for "ordered media IDs" and use it in generation and display.

---

### Issue 31 – Final post 3-dot menu: delete/edit after publish; more options

**Status:** Done (Apr 2026) — core owner **Edit / Delete**; “Make visible to…” still future  
**Area:** Backend + Mobile  
**Description:** Owner should edit or delete a published final post from the app.

**Fix applied:** **`DELETE /trips/[id]/final-post`** (owner-only) removes post + engagement; **`PUT`** allows edits after publish (generationStatus stays published). Mobile: **⋮** on **feed** and **post detail** (Edit → final-post screen, Delete → confirm + **`FeedProvider.removeHomeFeedPostById`**). **`FinalPostEditScreen`:** owner can save changes when already published.

---

### Issue 42 – Trip final post not clickable; only "View trip" is clickable

**Status:** Done (Apr 2026)  
**Area:** Mobile  
**Description:** Entire final post card should be tappable to open post detail; previously only "View trip" worked.

**Fix applied:** Feed card wraps media + body + engagement in **`InkWell`** → **`/post/TRIP_FINAL_POST/{id}`**; header (profile + owner ⋮) stays outside. **"View trip"** unchanged.

---

## 9. Share & Share Count

### Issue 32 – Share post link redirects to web; share count increases on any share

**Status:** Partial (Aug 2026) — app + API + GoRouter share allowlist + well-known **templates** in repo; **production** must set **`SHARE_LINK_BASE_URL`**, fill Apple Team ID / Android SHA-256 in `public/.well-known/*`, and redistribute the mobile build.

**Area:** Backend + Mobile  
**Description:** Shared links should open the app; **shareCount** should not rise on external / system-share sheet usage; in-app DM will use a dedicated source later.

**Fix applied:**  

1. **HTTPS share URL:** Built from **`SHARE_LINK_BASE_URL`** (mobile `.env` / dart-define); if unset, falls back to API origin without `/api` (often not ideal — set explicitly in prod). Path **`/share/{token}`** is served by **`src/app/share/[shareToken]/page.tsx`**, which opens **`tripthread://share/{token}`**, with a fallback link on the page.
2. **Native share text:** Includes **HTTPS link** plus **`Open in TripThread: tripthread://share/{token}`** so recipients can open the app even before Universal Links are configured.
3. **Mobile routing:** **`GoRoute` `/share/:shareToken` → `ShareLinkScreen`** resolves **`GET /api/shares/:token`** and navigates to **`/post/TRIP_FINAL_POST/{id}`**. **`DeepLinkService`** handles **`tripthread://`** host **`share`** and HTTPS paths **`/share/...`**. **iOS `Info.plist`:** **`tripthread`** URL scheme.
4. **Share count:** **`POST /shares`** accepts **`shareSource`**: **`SYSTEM_SHEET`** (default — system share / copy link from sheet) **does not** increment **`shareCount`**; **`IN_APP_DM`** increments (for future home → DM flow). Metadata stores **`shareSource`**.

**Remaining (ops):** Replace `TEAMID` / `REPLACE_WITH_SHA256` in `public/.well-known/*` and redeploy; ensure mobile release uses matching `SHARE_LINK_BASE_URL`; wire DM UI to call **`POST /shares`** with **`shareSource: "IN_APP_DM"`** when implemented.

---

## 10. Avatar & Profile Picture

### Issue 33 – Profile picture randomly deleted

**Status:** Partially addressed (Apr 2026)  
**Area:** Backend + Mobile + Cloudinary  
**Description:** Avatar sometimes disappears and must be re-uploaded.

**Fix plan:**  

1. **Backend:** Never delete user’s avatarUrl unless user explicitly removes it or account is deleted. Ensure no flow (e.g. OAuth overwrite, update profile) sets avatarUrl to null unintentionally.
2. **Cloudinary:** Ensure delete is only called when user explicitly removes photo, not on profile update.
3. **Mobile:** On profile load, if avatarUrl is null but user expects one, consider refetch from Google (if OAuth) or show placeholder; don’t overwrite with null.
4. **Logging:** Add logs when avatarUrl is updated or when Cloudinary delete is called for user media to trace future occurrences.

**Update (Apr 2026):** `PUT /users/[id]` only applies `avatarUrl` when a non-empty valid URL is present in the payload (partial updates no longer spread empty/omitted avatar into Prisma in a way that could clear it).

---

## 11. Comments UX (Alignment, Reply, Username)

### Issue 34 – "Unknown" username for a second when posting comment (latency)

**Status:** Done (Apr 2026)  
**Area:** Mobile  
**Description:** Brief "unknown" before real username appears when posting comment.

**Fix applied:** `CommentProvider.createComment` accepts `currentUserId` and `currentUserPreview` (`CommentUser` from `AuthProvider.currentUser`). `CommentComposer` passes them so the optimistic row includes the same avatar and `@username` as the server response. `/users/me` already returns `username` + `name` for the signed-in user.

---

### Issue 35 – Like button alignment in comment (beside reply, not beside comment)

**Status:** Done (Apr–May 2026)  
**Area:** Mobile  
**Description:** Like button should be beside the comment text, not on the action row below.

**Fix applied:** `CommentListItem`: **Row** with `Expanded(MentionText)` + like control on the **same row** as the comment body (trailing). Reply / View replies / Edit / Delete live in a **separate** `Wrap` row below.

**Files:** `mobile/lib/widgets/engagement/comment_list_item.dart` (list used by `comments_screen.dart` and `comment_bottom_sheet.dart`).

---

### Issue 36 – Edit/Delete button alignment changes when replies are shown

**Status:** Done (Apr–May 2026)  
**Area:** Mobile  
**Description:** When "Show replies" is open, action alignment shifted because like shared the row with actions.

**Fix applied:** Like moved to the **text row**; actions use a dedicated **`Wrap`** row (no `Expanded` + like). **Edit/Delete** only within **15 minutes** for own comments (and swipe-to-dismiss gated the same); reduces misleading buttons on old comments.

**Files:** `mobile/lib/widgets/engagement/comment_list_item.dart`.

---

### Issue 37 – No option to reply to replies (only to parent comment)

**Status:** Partial (Apr–May 2026)  
**Area:** Backend + Mobile  
**Description:** Can only reply to top-level comment; need reply-to-reply (e.g. to tag someone in thread, Instagram-style).

**Fix applied (mobile):** **Reply** is shown on **nested** `CommentListItem`s when `onReplyTap` is set; `comments_screen.dart` and `comment_bottom_sheet.dart` pass `_startReply(reply.id)` so the composer targets that comment as **`parentCommentId`**.

**Remaining:** Confirm API/threading semantics for deep reply trees and UI indentation if product wants full threading beyond one level under the root.

**Files:** `mobile/lib/widgets/engagement/comment_list_item.dart`, `comments_screen.dart`, `comment_bottom_sheet.dart`; backend `POST /comments` as needed.

---

### Issue 38 – Username not showing correctly when multiple users have same name

**Status:** Done (Apr 2026)  
**Area:** Backend + Mobile  
**Description:** Two users "Raj Bagaria" with different usernames; UI showed display name only and looked identical.

**Fix applied:**  

1. **Backend:** Comments already include `user` with `USER_PUBLIC_SELECT` (`username`, `name`, `avatarUrl`). Notification actors already select the same fields.  
2. **Mobile:** `user_display_labels.dart` — `userPrimaryLabel` / `userSecondaryName` / `userAvatarInitial`. **Comments:** `CommentListItem` shows @username + optional name line; `CommentUser.displayName` and **notifications** `UnifiedNotificationActor.displayName` prefer @username. **Profile** header and "Their Trips" title use primary/secondary pattern. **Trip participants** (list + search cards) use the same. **Notifications** trip-invite summary and avatars use primary label / username-first initial. **Replying to** uses `parentComment.user.displayName` (username-first).

---

### Issue 41 – Like button size difference in comments (unliked vs liked)

**Status:** Done (Apr–May 2026)  
**Area:** Mobile  
**Description:** Unliked heart is small (expected); liked heart scaled up with animation and looked inconsistent.

**Fix applied:** Removed scale animation; **`IconButton`** with fixed **`22px`** icon and **`44×44`** tap target; **`favorite_border` / `favorite`** at same size.

**Files:** `mobile/lib/widgets/engagement/comment_list_item.dart` (`_CommentLikeButton`).

---

## 12. Back Button & Navigation

### Issue 26 – Back from Discover / Create trip / Profile should go to Home then Exit dialog

**Status:** Done (Apr 2026)  
**Area:** Mobile  
**Description:** From Discover, Create trip, or Profile, first back should go to Home (Feed); from Home Feed, back should show "Exit app?" (Cancel / Exit).

**Fix applied:**  

1. **`HomeScreen`:** `PopScope` with `canPop: false` — back on Trips / Discover / Profile **tabs** switches to **Feed** first; second back on Feed shows exit dialog (`SystemNavigator.pop`).  
2. **`CreateTripScreen`:** `PopScope` with `canPop: false`; system back and close icon `go('/home', extra: {'explicitHome': true})` so the user always lands on the shell (Feed-first behavior), then a second back triggers the home exit dialog.  
3. **`ProfileScreen` (`/profile/:userId`):** Same as create-trip — back/leading always `go('/home', explicitHome: true)` so the next back is handled by `HomeScreen` (Feed → exit dialog). *Trade-off:* in-stack navigation to profile no longer pops one level; product choice per Issue 26 spec.

---

## 13. Summary Table


| #   | Title                                | Status               | Area                         |
| --- | ------------------------------------ | -------------------- | ---------------------------- |
| 1   | Public/private toggle                | Done                 | -                            |
| 2   | Notifications for follow             | Done (Apr 2026)      | Backend + Mobile             |
| 3   | Realtime profile stats               | Done (Apr 2026)      | Mobile                       |
| 4   | Follow request back gesture          | Done (Apr 2026)      | Mobile                       |
| 5   | Trip cover anytime                   | Done (Apr 2026)      | Backend + Mobile             |
| 6   | Extend trip end date                 | Open                 | Backend + Mobile             |
| 7   | Optional dates; dynamic start/end    | Open                 | Backend + Mobile + Scheduler |
| 8   | Start/end time & timezone            | Open                 | Backend + Scheduler          |
| 9   | Logout all devices                   | Partial (Apr 2026)   | Backend + Mobile             |
| 10  | DM icon instead of search            | Done (placeholder)   | Mobile                       |
| 11  | Continue & Replace trip              | Open                 | Backend + Mobile             |
| 12  | DP/trips after follow                | Done (Apr 2026)      | Backend + Mobile             |
| 12b | Bubble + redirect for participants   | Done (Apr 2026)      | Mobile + Backend             |
| 13  | Discover not updated / trips missing | Partial (Apr 2026)   | Backend + Mobile             |
| 13b | Delete thread entries                | Done (Apr 2026)      | Backend + Mobile             |
| 14  | Text edit (15 min author) + delete; location in-place TBD | Partial (Apr–May 2026) | Backend + Mobile |
| 15  | Realtime entries                     | Open                 | Architecture                 |
| 16  | Scroll to latest; paginate entries   | Done (Apr 2026)      | Backend + Mobile             |
| 18  | Trip cover upload broken             | Done (Apr 2026)      | Backend + Mobile             |
| 19  | Avatar from Google sometimes         | Open                 | Backend + Mobile             |
| 20  | Participant exit trip                | Done (Apr–May 2026)  | Backend + Mobile             |
| 21  | FAB order (+ camera bubble)          | Partial (Apr 2026)   | Mobile                       |
| 22  | Profile icons re-organize            | Open                 | Mobile                       |
| 23  | Trips on other user profile          | Done (Apr 2026)      | Backend + Mobile             |
| 24  | Final post button on old posts       | Done (Apr 2026)      | Backend + Mobile             |
| 25  | View others’ profile picture         | Done (Apr 2026)      | Mobile                       |
| 26  | Back → Home then Exit dialog         | Done (Apr 2026)      | Mobile                       |
| 27  | View participants list               | Done (Apr 2026)      | Backend + Mobile             |
| 28  | Final post 403 for participants      | Done (Apr 2026)      | Backend                      |
| 29  | "Your trip" → trip name              | Done (Apr 2026)      | Backend + Scheduler          |
| 30  | Draft image order                    | Open                 | Backend + Mobile             |
| 31  | Final post 3-dot menu                | Done (Apr 2026)      | Backend + Mobile             |
| 32  | Share link + share count             | Partial (Apr 2026)   | Backend + Mobile             |
| 33  | Profile picture deleted              | Partial (Apr 2026)   | Backend + Mobile             |
| 34  | Unknown username flash               | Done (Apr 2026)      | Mobile                       |
| 35  | Like button alignment                | Done (Apr–May 2026)  | Mobile                       |
| 36  | Edit/Delete alignment in replies     | Done (Apr–May 2026)  | Mobile                       |
| 37  | Reply to reply                       | Partial (Apr–May 2026) | Backend + Mobile           |
| 38  | Username for same name               | Done (Apr 2026)      | Backend + Mobile             |
| 40  | Trips on participant profile         | Same as 23           | Backend + Mobile             |
| 41  | Like button size                     | Done (Apr–May 2026)  | Mobile                       |
| 42  | Final post card clickable            | Done (Apr 2026)      | Mobile                       |


---

## Suggested implementation order

*Completed via PR #39–43 (including follow-ups): e.g. 4, 12, 16–18, 20, 23–29, 34–36, 38, 41, and Issue 14’s text/delete/15m scope — skip those unless regressions appear.*

1. **Stability / partial:** 9 (logout all devices), 13 (discover completeness), 21 (FAB order), 33 (profile picture edge cases).
2. **Comments (remaining):** 37 (deeper reply threading / API if product wants full trees).
3. **Trip product:** 6, 7, 8, 11 (extend trip, optional dates, timezone, replace/continue trip).
4. **Thread / feed:** 15 (realtime or polling), **14** (location/check-in in-place edit only).
5. **Profile & polish:** 19, 22, 30 (31/42 done; 32 ops: Universal Links + **`SHARE_LINK_BASE_URL`**).

After you review this document, we can start implementing from the list above or in an order you prefer.