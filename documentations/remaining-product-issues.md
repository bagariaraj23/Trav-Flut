# TripThread — identified issues still to fix

Updated 2026-10-18 after the stacked review branches (database performance, Warm UI, trip create).

The original Rajasthan testing write-up lived at the repo root as `IDENTIFIED_ISSUES_AND_FIX_PLANS.md`. That filename is gitignored (local-only) and was removed from git in `e337fb4`. This file is the tracked status. Statuses below are against the trip-create tip, which contains the database and Warm UI commits.

## Already done (do not reopen)

Privacy toggle, follow notifications, profile stat refresh, follow-request back gesture, cover update, DM icon placeholder, discover trips, thread entry delete, thread pagination, cover upload, leave trip, other users’ trips, participant list, avatar enlarge, back-to-home, final-post view/publish/403/title/menu/card tap, and the comment alignment / unknown-name / like-size fixes.

Trip dates (issues 6, 7, and 8) are implemented on `feat-trip-create-ux`: optional start and end, `PATCH /trips/[id]/dates`, UTC instants plus `scheduleTimezone`, and the scheduler using the same clock. Open-ended trips keep `endDate` null. Apply migration `20261014150000_trip_open_ended_schedule`.

Warm UI consistency landed on `feat-ui-warm-polish`: feed, discover, profile, notifications, settings, and share use `AppFeedback` (theme error, rose attention badges, warm avatar fallbacks, trip-palette entry icons). Map pin colors stay the classic legend so destinations, the viewer, and visited places stay distinguishable.

## Remaining product issues

| # | Issue | Status | What is still left |
| --- | --- | --- | --- |
| 9 | Log out of all devices | Partial | Current device is forced out on 401. Other devices keep working until the access token expires. Revoke every refresh token and fail the next refresh on those devices. |
| 11 | Continue & Replace an upcoming trip | Open | If the traveller continues and replaces, delete the previous upcoming trip when it has not started. If it has started, end it through the normal end-trip path. |
| 14 | In-place location / check-in edit | Partial | Text edit inside 15 minutes and delete are shipped. Location and check-in still cannot be corrected in place. |
| 15 | Realtime thread | Open | A new entry is invisible to other people on the thread until they leave and reopen. Needs a push (WebSocket or equivalent), not another poll-only refresh. |
| 19 | Google avatar sometimes missing | Open | OAuth login should set the avatar from the Google profile photo every time it is present. |
| 21 | Owner bubble vs create button | Partial | The create, camera, and owner bubble still collide on some thread layouts. Order should stay create, camera, then bubble, with no overlap. |
| 22 | Profile icon clutter | Open | Follow requests and trip invites still compete with the rest of the profile chrome. Group them so the profile reads as a person, not a toolbar. |
| 30 | Final-post image reorder | Open | Draft media should be reorderable. Selection order is not a substitute for an explicit order. |
| 31 | “Make visible to…” | Future | Owner edit and delete of a published final post are done. Audience controls are not. |
| 32 | Share links | Ops | App routing and well-known templates are in the repo. Production still needs `SHARE_LINK_BASE_URL`, the Apple Team ID, the Play signing SHA-256, and a redistributed build. In-app DM share is deferred. |
| 33 | Profile picture randomly deleted | Partial | Avatar can still disappear and need a re-upload. Trace Cloudinary destroy vs. profile PATCH so a failed upload cannot wipe a good URL. |
| 37 | Reply to a reply | Partial | Replies exist on the parent comment. A reply should be able to target another reply and name that person, the way a social thread does. |

## UX follow-ups (not regressions)

- Map legend and the location pin stay red / green / blue on purpose.
- Flutter widget tests were not run in this environment (no Flutter SDK). Backend Vitest is the check that older flows still pass.
- Empty and error copy now speaks in the product voice (“Couldn’t load your feed”, “You’re following them”). Do not reintroduce Material green and red snackbars on these screens.
