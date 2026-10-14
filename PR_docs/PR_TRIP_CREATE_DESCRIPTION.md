## Summary

A new trip starts when it is created and stays open until the owner taps End trip. Start later and Set an end are optional date-and-time controls. Times are stored as UTC instants and shown in the viewer's zone. An unset trip type is Solo and becomes Group when someone else joins.

**Branch:** `feat-trip-create-ux` · **Base:** `feat-ui-warm-polish`  
**PR:** draft, stacked on PR #51 (Warm UI)

Apply migration `20261014150000_trip_open_ended_schedule` before using this against a database. iOS needs a pod install for `flutter_timezone`.

## Changes Made

### Create and schedule

*   `POST /trips` treats `startDate` and `endDate` as optional. A missing start is `now` and the trip is `ONGOING`. A missing end stays null. A future start stays `UPCOMING`.
*   Instants are stored as sent (UTC). They are no longer truncated to UTC midnight.
*   `scheduleTimezone` is the IANA zone the wall time was chosen in. Comparisons use the UTC columns only.
*   `PATCH /trips/[id]/dates` lets the owner change a future start, or set, change, or clear an end, while the trip is not ended.
*   `POST /trips/[id]/end` still ends an ongoing trip and writes the final post. Ending a trip that is still upcoming marks it ended and skips the final post.
*   `src/lib/tripSchedule.ts` is the shared start/end rule. Trip list, trip detail, and `/trips/status` apply it on read so the app does not wait for the hourly scheduler. The scheduler uses the same UTC comparison and starts open-ended trips (`endDate` null).

### Trip type

*   No chosen type means `SOLO` and `typeSetByUser` false.
*   Joining or leaving updates the type only when the user did not set it: two or more people become `GROUP`, and a drop back to the owner returns `SOLO`.
*   `COUPLE` and `FAMILY` change only when the user selects them.

### Mobile

*   Create trip drops the required start and end fields. Start later and Set an end open a date picker and then a time picker.
*   `formatTripInstant` converts the UTC instant to the device zone and appends the zone abbreviation. Legacy UTC-midnight rows with no `scheduleTimezone` stay a calendar date.
*   Trip detail, home, invitations, and the final-post editor use that formatter. The owner can end an upcoming trip, and can set, change, or remove an end time.

### Schema

Migration `20261014150000_trip_open_ended_schedule`:

*   `trips.endDate` is nullable.
*   `trips.scheduleTimezone` (text, null on old rows).
*   `trips.typeSetByUser` (boolean, default false). Existing rows with a type are marked user-set so they are not rewritten.

## How to Test

```bash
npm run test:scheduler
npx vitest run tests/unit/trip-schedule.unit.test.ts tests/unit/validation-flows.unit.test.ts
cd mobile && flutter test test/utils/trip_time_format_test.dart
```

Manual:

*   Create a trip with only a title and a destination. It is ongoing, has no end, and shows the start time in the device zone.
*   Turn on Start later, pick a future date and time, and confirm the trip stays upcoming until that instant.
*   Turn on Set an end, then change and clear that end from trip detail.
*   End an upcoming trip and confirm there is no final post. End an ongoing trip and confirm the final post is created.
*   Leave the type unset, add a participant, and confirm the trip becomes Group. Pick Couple first and confirm it stays Couple.
*   20 Mar 2026 18:30 in `Asia/Kolkata` is stored as `2026-03-20T13:00:00.000Z` and renders as 6:30 PM IST or 8:00 AM ET.

## Notes for Reviewers

*   This branch is stacked on `feat-ui-warm-polish` (PR #51), not `main`.
*   `IDENTIFIED_ISSUES_AND_FIX_PLANS.md` is gitignored. Issues 6, 7, and 8 are marked addressed in the local copy. `documentations/context.json` carries the same schedule rules.
*   The hourly scheduler can still lag by up to an hour for trips nobody opens. Opening the trip list, detail, or status catches the transition.
*   Historical trips stay date-only. New and edited instants show a converted clock time.
