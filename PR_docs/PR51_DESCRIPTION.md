## Summary

Applies the Warm visual system across the Flutter app: cream canvas, ink text, terracotta accent, Playfair Display titles, and DM Sans body. It also adds a cover placeholder, a safe avatar initial for a blank name, readable status text on outgoing chat bubbles, and tighter auth spacing on short phones.

**Branch:** `feat-ui-warm-polish` · **Base:** `main` (includes merged **PR #50** trip expense ledger)  
**PR:** https://github.com/bagariaraj23/Trav-Flut/pull/51

## Changes Made

### Palette (`mobile/lib/utils/app_theme.dart`)

| Token | Value | Role |
| --- | --- | --- |
| `ink` | `#1C1917` | Light primary, titles, outgoing chat bubble |
| `cream` | `#FAF8F4` | Scaffold, app bar, light `onPrimary` |
| `card` | `#FFFFFF` | Cards and surfaces |
| `accent` | `#C2692A` | Terracotta secondary, filled buttons |
| `accentDark` | `#D4773A` | Dark-theme accent |
| `darkBackground` | `#18140F` | Dark scaffold |
| `onSecondary` | white | Label on terracotta buttons |

Buttons use `colorScheme.secondary` with white `onSecondary`. Outgoing chat uses `colorScheme.primary` (ink) with `onPrimary` (cream) for the message, time, and seen state.

### Layout and widgets

*   `AppLayout.authSpacing`: below 700px height, page padding is 16 and the top/logo gaps shrink. Taller phones keep padding 24.
*   `AppLayout.reading`: centered column, max width 720 once the window is wide (`shortestSide >= 600`, or landscape at that width).
*   `TripCoverPlaceholder` when a trip has no cover.
*   `ChatAvatar` / `userAvatarInitial`: a blank or null name renders `U` instead of indexing an empty string.
*   Thread cards, logo, text fields, auth, trip, thread, chat, and **Money** screens pick up the same tokens (expense behavior is from PR #50; this PR is visual only).

### Tests

*   `test/utils/warm_theme_test.dart`
*   `test/widgets/chat_avatar_test.dart` (blank name → `U`)
*   `test/widgets/trip_cover_placeholder_test.dart`
*   `test/widgets/like_button_test.dart` (timer settle fix, regression)

## How to Test

```bash
cd mobile && flutter test \
  test/utils/warm_theme_test.dart \
  test/widgets/chat_avatar_test.dart \
  test/widgets/trip_cover_placeholder_test.dart \
  test/widgets/like_button_test.dart
```

Manual: login on a short phone (spacing should not push the button off screen), a trip with no cover, a chat with an empty display name, an outgoing bubble whose time and “Seen” stay readable on the dark ink fill, and the Money pane after opening an ongoing trip (thread ↔ money swipe still works with Warm tokens).

## Notes for Reviewers

*   **PR #50 is merged to `main`.** Retarget this PR to `main` and rebase `feat-ui-warm-polish` onto latest `main` so the diff is Warm-theme-only (the branch was originally opened against `feat-expenses-split`).
*   The accent is `#C2692A`, not `#D95338`. The canvas is `#FAF8F4`, not `#FBF8F3`. Cards are white. Body text is ink `#1C1917`.
*   Outgoing bubbles are ink with cream text. Terracotta is the button and secondary color.
*   Theme/avatar/cover test fixes are on the branch (`16abadb` and related commits). See `PR51_COMPLETE_REVIEW.md` for review notes.

## Related

*   Merged dependency: [PR #50](https://github.com/bagariaraj23/Trav-Flut/pull/50) — trip expense ledger (Money pane, splits, settle-up).
